-- Backend-only profile authentication. No email, GitHub token, or OAuth secret is stored.
do $$ begin if not exists(select 1 from pg_roles where rolname='trainer_api') then create role trainer_api nologin noinherit; end if; end $$;
do $$ begin
 if exists(select 1 from pg_roles where rolname='trainer_api' and (rolsuper or rolbypassrls or rolcreatedb or rolcreaterole or rolinherit))
  or exists(select 1 from pg_auth_members where member=(select oid from pg_roles where rolname='trainer_api')) then
  raise exception 'trainer_api must be an isolated least-privilege role';
 end if;
end $$;
grant usage on schema trainer_internal to trainer_api;
create table trainer_internal.accounts (
 owner_id uuid primary key default gen_random_uuid(),
 github_id text not null unique check(length(github_id) between 1 and 100),
 alias text not null check(length(alias) between 1 and 100)
);
insert into trainer_internal.accounts(owner_id,github_id,alias)
 select owner_id,github_id,alias from public.trainer_profiles;
create table trainer_internal.profile_sessions (
 session_id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references trainer_internal.accounts(owner_id) on delete cascade,
 access_hash text not null unique check(length(access_hash)=64),
 refresh_hash text not null unique check(length(refresh_hash)=64),
 access_until timestamptz not null default clock_timestamp()+interval '15 minutes',
 refresh_until timestamptz not null default clock_timestamp()+interval '30 days'
);
create index profile_sessions_owner on trainer_internal.profile_sessions(owner_id);
alter table trainer_internal.accounts enable row level security;
alter table trainer_internal.profile_sessions enable row level security;
revoke all on trainer_internal.accounts,trainer_internal.profile_sessions from public,anon,authenticated,trainer_api;
alter table public.trainer_profiles drop constraint trainer_profiles_owner_id_fkey;
alter table public.trainer_profiles add foreign key(owner_id) references trainer_internal.accounts(owner_id) on delete cascade;
alter table trainer_internal.growth_policy drop constraint growth_policy_owner_id_fkey;
alter table trainer_internal.growth_policy add foreign key(owner_id) references trainer_internal.accounts(owner_id) on delete cascade;
alter table trainer_internal.growth_audit drop constraint growth_audit_owner_id_fkey;
alter table trainer_internal.growth_audit add foreign key(owner_id) references trainer_internal.accounts(owner_id) on delete cascade;

-- Legacy Auth identities retain their exact save owner UUID. The alias never selects an owner.
create or replace function public.ensure_trainer_profile() returns uuid
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); identity_row record; account trainer_internal.accounts; display_alias text;
begin
 if u is null then raise insufficient_privilege; end if;
 select * into account from trainer_internal.accounts where owner_id=u;
 if not found then
  select provider_id,identity_data into identity_row from auth.identities where user_id=u and provider='github' limit 1;
  if not found then raise insufficient_privilege; end if;
  display_alias:=coalesce(identity_row.identity_data->>'user_name',identity_row.identity_data->>'preferred_username');
  insert into trainer_internal.accounts(owner_id,github_id,alias) values(u,identity_row.provider_id,display_alias) returning * into account;
 end if;
 insert into public.trainer_profiles(owner_id,github_id,alias) values(u,account.github_id,account.alias)
  on conflict(owner_id) do update set github_id=excluded.github_id,alias=excluded.alias;
 return u;
end $$;

create or replace function trainer_internal.check_session() returns void
language plpgsql security definer set search_path='' as $$
declare sid uuid; u uuid:=auth.uid();
begin
 if u is null then raise insufficient_privilege; end if;
 begin sid:=(auth.jwt()->>'session_id')::uuid; exception when invalid_text_representation then raise insufficient_privilege; end;
 if sid is null or not (
  exists(select 1 from auth.sessions s where s.id=sid and s.user_id=u and (s.not_after is null or s.not_after>clock_timestamp()))
  or exists(select 1 from trainer_internal.profile_sessions s where s.session_id=sid and s.owner_id=u and s.access_until>clock_timestamp())
 ) then raise insufficient_privilege; end if;
end $$;

-- Caller identity is established from a hashed opaque token, never request owner/alias fields.
create function trainer_internal.bind_profile_session(token_hash text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare session trainer_internal.profile_sessions; account trainer_internal.accounts;
begin
 select * into session from trainer_internal.profile_sessions where access_hash=token_hash and access_until>clock_timestamp();
 if not found then raise insufficient_privilege; end if;
 select * into account from trainer_internal.accounts where owner_id=session.owner_id;
 perform set_config('request.jwt.claim.sub',session.owner_id::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',session.owner_id,'session_id',session.session_id)::text,true);
 -- Compatibility with local Auth fixtures, which intentionally use discrete claim settings.
 perform set_config('request.jwt.claim.session_id',session.session_id::text,true);
 return jsonb_build_object('id',session.owner_id,'alias',account.alias);
end $$;

create function trainer_internal.open_profile_session(github_id text,alias text,access_hash text,refresh_hash text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare account trainer_internal.accounts; legacy record;
begin
 if github_id !~ '^[0-9]+$' or alias !~ '^[A-Za-z0-9][A-Za-z0-9-]{0,38}$' then raise insufficient_privilege; end if;
 -- Serialize first sign-ins for the same immutable provider ID across server instances.
 perform pg_advisory_xact_lock(hashtextextended(github_id,0));
 select * into account from trainer_internal.accounts a where a.github_id=open_profile_session.github_id;
 if not found then
  select user_id into legacy from auth.identities i where i.provider='github' and i.provider_id=open_profile_session.github_id limit 1;
  insert into trainer_internal.accounts(owner_id,github_id,alias)
   values(coalesce(legacy.user_id,gen_random_uuid()),github_id,alias) returning * into account;
 else
  update trainer_internal.accounts a set alias=open_profile_session.alias where a.owner_id=account.owner_id returning * into account;
 end if;
 delete from trainer_internal.profile_sessions s where s.owner_id=account.owner_id and s.refresh_until<clock_timestamp();
 insert into trainer_internal.profile_sessions(owner_id,access_hash,refresh_hash) values(account.owner_id,access_hash,refresh_hash);
 return jsonb_build_object('id',account.owner_id,'alias',account.alias);
end $$;

create function trainer_internal.rotate_profile_session(old_refresh_hash text,new_access_hash text,new_refresh_hash text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare session trainer_internal.profile_sessions; account trainer_internal.accounts;
begin
 select * into session from trainer_internal.profile_sessions s where s.refresh_hash=old_refresh_hash and s.refresh_until>clock_timestamp() for update;
 if not found then raise insufficient_privilege; end if;
 update trainer_internal.profile_sessions s set access_hash=new_access_hash,refresh_hash=new_refresh_hash,access_until=clock_timestamp()+interval '15 minutes' where s.session_id=session.session_id;
 select * into account from trainer_internal.accounts where owner_id=session.owner_id;
 return jsonb_build_object('id',account.owner_id,'alias',account.alias);
end $$;

create function trainer_internal.profile_request(token_hash text,action text,command jsonb default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare identity jsonb;
begin
 identity:=trainer_internal.bind_profile_session(token_hash);
 case action
 when 'user' then return identity;
 when 'read' then return trainer_internal.read_owned_save();
 when 'write' then return trainer_internal.write_trainer_save((command->>'expectedRevision')::bigint,(command->>'requestID')::uuid,
  command->>'operation',command->'state',coalesce(command->'rules','{"growthDifficulty":1,"shopDifficulty":1}'::jsonb));
 when 'logout' then delete from trainer_internal.profile_sessions where access_hash=token_hash;return '{}'::jsonb;
 else raise insufficient_privilege;
 end case;
end $$;
revoke all on function trainer_internal.bind_profile_session(text),trainer_internal.open_profile_session(text,text,text,text),
 trainer_internal.rotate_profile_session(text,text,text),trainer_internal.profile_request(text,text,jsonb) from public,anon,authenticated,trainer_api;
grant execute on function trainer_internal.open_profile_session(text,text,text,text),trainer_internal.rotate_profile_session(text,text,text),
 trainer_internal.profile_request(text,text,jsonb) to trainer_api;
