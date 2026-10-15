-- Display-only encounters: private normalized rooms and selections, separate from growth saves.
create table trainer_internal.encounter_rooms (
 id uuid primary key default gen_random_uuid(), code_hash text not null unique,
 revision bigint not null default 1, expires_at timestamptz not null default clock_timestamp()+interval '30 minutes',
 closed boolean not null default false
);
create table trainer_internal.encounter_members (
 room_id uuid references trainer_internal.encounter_rooms(id) on delete cascade,
 owner_id uuid references trainer_internal.accounts(owner_id) on delete cascade,
 slot smallint not null check(slot in (0,1)), selected_id text,
 primary key(room_id,owner_id), unique(room_id,slot)
);
create index encounter_members_owner on trainer_internal.encounter_members(owner_id);
create index encounter_rooms_expiry on trainer_internal.encounter_rooms(expires_at);
create table trainer_internal.encounter_attempts (
 owner_id uuid primary key references trainer_internal.accounts(owner_id) on delete cascade,
 window_start timestamptz not null, attempts integer not null check(attempts between 1 and 21)
);
alter table trainer_internal.encounter_rooms enable row level security;
alter table trainer_internal.encounter_members enable row level security;
alter table trainer_internal.encounter_attempts enable row level security;
revoke all on trainer_internal.encounter_rooms,trainer_internal.encounter_members,trainer_internal.encounter_attempts from public,anon,authenticated,trainer_api;

create function trainer_internal.encounter_choices(player uuid,wanted text default null) returns jsonb
language sql stable security definer set search_path='' as $$
 with individuals as (
  select s.core->'active' as mon, (s.core->'active'->'profile'->>'instanceID') as individual,
   (s.core->'active'->'pathIDs'->>((s.core->'active'->>'stageIndex')::integer))::integer as species
  from public.trainer_saves s where s.owner_id=player and s.core->'active'->'profile'->>'instanceID' is not null
   and (wanted is null or s.core->'active'->'profile'->>'instanceID'=wanted)
  union all
  select c.detail||jsonb_build_object('isShiny',c.shiny),c.individual_id,c.final_id from public.trainer_collection c where c.owner_id=player and (wanted is null or c.individual_id=wanted)
 ) select coalesce(jsonb_agg(jsonb_build_object('id',individual,'speciesID',species,
  'level',coalesce((mon->'profile'->>'level')::integer,1),'isShiny',coalesce((mon->>'isShiny')::boolean,false),
  'unownForm',mon->>'unownForm') order by individual),'[]'::jsonb) from individuals
 where individual is not null and species between 1 and 649
$$;

create function trainer_internal.encounter_view(room uuid,player uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',r.id,'revision',r.revision,'closed',r.closed or r.expires_at<=clock_timestamp(),
  'members',coalesce((select jsonb_agg(jsonb_build_object('isSelf',m.owner_id=player,'alias',a.alias,
   'pokemon',case when m.selected_id is not null then (select choice-'id' from jsonb_array_elements(trainer_internal.encounter_choices(m.owner_id,m.selected_id)) choice
    where choice->>'id'=m.selected_id limit 1) else null end) order by m.slot)
   from trainer_internal.encounter_members m join trainer_internal.accounts a on a.owner_id=m.owner_id where m.room_id=r.id),'[]'::jsonb))
 from trainer_internal.encounter_rooms r where r.id=room
$$;

create function trainer_internal.encounter_request(token_hash text,action text,command jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare identity jsonb; player uuid; target trainer_internal.encounter_rooms; code text; n integer; room uuid; selection text;
begin
 identity:=trainer_internal.bind_profile_session(token_hash); player:=(identity->>'id')::uuid;
 if action='roster' then
  select r.* into target from trainer_internal.encounter_rooms r join trainer_internal.encounter_members m on m.room_id=r.id
   where m.owner_id=player and not r.closed and r.expires_at>clock_timestamp() limit 1;
  return jsonb_build_object('choices',trainer_internal.encounter_choices(player),'room',
   case when target.id is not null then trainer_internal.encounter_view(target.id,player) else null end);
 end if;
 if action in ('create','join') then
  -- Commit failed guesses as well: expected errors are returned, not raised inside this transaction.
  insert into trainer_internal.encounter_attempts values(player,clock_timestamp(),1)
  on conflict(owner_id) do update set
   attempts=case when encounter_attempts.window_start<clock_timestamp()-interval '1 minute' then 1 else least(21,encounter_attempts.attempts+1) end,
   window_start=case when encounter_attempts.window_start<clock_timestamp()-interval '1 minute' then clock_timestamp() else encounter_attempts.window_start end
  returning attempts into n;
  if n>20 then return jsonb_build_object('error','rate_limited'); end if;
  perform pg_advisory_xact_lock(hashtextextended(player::text,42));
  if exists(select 1 from trainer_internal.encounter_members m join trainer_internal.encounter_rooms r on r.id=m.room_id
   where m.owner_id=player and not r.closed and r.expires_at>clock_timestamp()) then
   return jsonb_build_object('error','already_in_room');
  end if;
  if action='create' then
   code:=replace(gen_random_uuid()::text,'-','');
   insert into trainer_internal.encounter_rooms(code_hash) values(encode(sha256(convert_to(code,'UTF8')),'hex')) returning * into target;
   insert into trainer_internal.encounter_members values(target.id,player,0,null);
   return trainer_internal.encounter_view(target.id,player)||jsonb_build_object('inviteCode',code);
  end if;
  code:=command->>'code';
  if code is null or code !~ '^[a-f0-9]{32}$' then return jsonb_build_object('error','invalid_invitation'); end if;
  select * into target from trainer_internal.encounter_rooms r where r.code_hash=encode(sha256(convert_to(code,'UTF8')),'hex') for update;
  if not found or target.closed or target.expires_at<=clock_timestamp() then return jsonb_build_object('error','invalid_invitation'); end if;
  if exists(select 1 from trainer_internal.encounter_members where room_id=target.id and slot=1) then return jsonb_build_object('error','room_full'); end if;
  insert into trainer_internal.encounter_members values(target.id,player,1,null);
  update trainer_internal.encounter_rooms set revision=revision+1 where id=target.id;
  return trainer_internal.encounter_view(target.id,player);
 end if;
 begin room:=(command->>'roomID')::uuid; exception when invalid_text_representation then raise insufficient_privilege; end;
 select * into target from trainer_internal.encounter_rooms r where r.id=room for update;
 if not found or not exists(select 1 from trainer_internal.encounter_members where room_id=room and owner_id=player) then raise insufficient_privilege; end if;
 if action='read' then return trainer_internal.encounter_view(room,player); end if;
 if target.closed or target.expires_at<=clock_timestamp() then return jsonb_build_object('error','room_closed'); end if;
 if (command->>'expectedRevision')::bigint is distinct from target.revision then return jsonb_build_object('error','stale_revision'); end if;
 if action='select' then
  selection:=command->>'individualID';
  if not exists(select 1 from jsonb_array_elements(trainer_internal.encounter_choices(player,selection)) choice where choice->>'id'=selection) then
   return jsonb_build_object('error','not_owned'); end if;
  update trainer_internal.encounter_members set selected_id=selection where room_id=room and owner_id=player;
 elsif action='leave' then
  update trainer_internal.encounter_rooms set closed=true where id=room;
 else raise insufficient_privilege;
 end if;
 update trainer_internal.encounter_rooms set revision=revision+1 where id=room;
 return trainer_internal.encounter_view(room,player);
end $$;
revoke all on function trainer_internal.encounter_choices(uuid,text),trainer_internal.encounter_view(uuid,uuid),trainer_internal.encounter_request(text,text,jsonb) from public,anon,authenticated,trainer_api;
grant execute on function trainer_internal.encounter_request(text,text,jsonb) to trainer_api;
