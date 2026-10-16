-- Durable oversized-growth admission; retains the 25M burst and 100k/second budget.
create table trainer_internal.growth_wait (
 owner_id uuid primary key references trainer_internal.accounts(owner_id) on delete cascade,
 request_id uuid not null,
 expected_revision bigint not null check(expected_revision>=0),
 payload_hash text not null check(length(payload_hash)=64),
 ready_at timestamptz not null
);
alter table trainer_internal.growth_wait enable row level security;
revoke all on trainer_internal.growth_wait from public,anon,authenticated,trainer_api;

create or replace function trainer_internal.write_trainer_save(p_expected_revision bigint,p_request_id uuid,p_operation text,p_state jsonb,
 p_rules jsonb default '{"growthDifficulty":1,"shopDifficulty":1}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid; previous jsonb; policy trainer_internal.growth_policy; result jsonb; delta jsonb;
 available_credit numeric; instant timestamptz:=clock_timestamp(); old_rules jsonb; prior_audit trainer_internal.growth_audit;
 queued trainer_internal.growth_wait; earned numeric; state_digest text; wait_seconds numeric;
begin
 perform trainer_internal.check_session();
 u:=public.ensure_trainer_profile();
 select * into prior_audit from trainer_internal.growth_audit where owner_id=u and request_id=p_request_id;
 if found then
  if prior_audit.rules is distinct from p_rules then raise sqlstate 'PT409' using message='request_reused'; end if;
  return trainer_internal.write_snapshot(p_expected_revision,p_request_id,p_operation,p_state);
 end if;
 -- Legacy request IDs cannot become an escape hatch around the new policy.
 if exists(select 1 from public.trainer_save_operations where owner_id=u and request_id=p_request_id) then
  raise sqlstate 'PT409' using message='legacy_request_reused'; end if;
 previous:=trainer_internal.read_snapshot();
 if coalesce((previous->>'revision')::bigint,0)<>p_expected_revision then raise sqlstate 'PT409' using message='save_conflict'; end if;
 insert into trainer_internal.growth_policy(owner_id) values(u) on conflict do nothing;
 select * into policy from trainer_internal.growth_policy where owner_id=u for update;
 old_rules:=policy.rules;
 delta:=trainer_internal.check_transition(previous->'state',p_state,old_rules,p_rules);
 if coalesce(p_state->>'lastDate','')<>'' and abs((p_state->>'lastDate')::date-instant::date)>1 then
  raise sqlstate 'PT422' using message='invalid_usage_date'; end if;
 available_credit:=least(25000000,policy.token_credit+greatest(0,extract(epoch from instant-policy.refilled_at))*100000);
 earned:=(delta->>'earned')::numeric;
 if earned>25000000 then
  state_digest:=encode(sha256(convert_to(jsonb_build_object('state',p_state,'rules',p_rules)::text,'UTF8')),'hex');
  select * into queued from trainer_internal.growth_wait where owner_id=u for update;
  if queued.request_id=p_request_id and (queued.payload_hash<>state_digest or queued.expected_revision<>p_expected_revision) then
   raise sqlstate 'PT409' using message='request_reused';
  end if;
  if queued.request_id is distinct from p_request_id or queued.expected_revision is distinct from p_expected_revision then
   wait_seconds:=ceil(greatest(0,earned-available_credit)/100000);
   insert into trainer_internal.growth_wait(owner_id,request_id,expected_revision,payload_hash,ready_at)
    values(u,p_request_id,p_expected_revision,state_digest,instant+wait_seconds*interval '1 second')
    on conflict(owner_id) do update set request_id=excluded.request_id,expected_revision=excluded.expected_revision,
     payload_hash=excluded.payload_hash,ready_at=excluded.ready_at;
   return jsonb_build_object('error','growth_rate_limit','retryAfter',greatest(1,least(3600,wait_seconds)));
  end if;
  if instant<queued.ready_at then
   return jsonb_build_object('error','growth_rate_limit','retryAfter',greatest(1,least(3600,ceil(extract(epoch from queued.ready_at-instant)))));
  end if;
  available_credit:=earned;
 elsif earned>available_credit then
  return jsonb_build_object('error','growth_rate_limit','retryAfter',greatest(1,ceil((earned-available_credit)/100000)));
 end if;
 if (case when policy.reward_day=instant::date then policy.rewards_today else 0 end)+(delta->>'rewards')::integer>30 then
  raise sqlstate 'PT429' using message='reward_rate_limit'; end if;
 delete from trainer_internal.growth_wait where owner_id=u;
 result:=trainer_internal.write_snapshot(p_expected_revision,p_request_id,p_operation,p_state);
 update trainer_internal.growth_policy set rules=p_rules,token_credit=available_credit-(delta->>'earned')::numeric,
  refilled_at=instant,reward_day=instant::date,
  rewards_today=(case when policy.reward_day=instant::date then policy.rewards_today else 0 end)+(delta->>'rewards')::integer where owner_id=u;
 insert into trainer_internal.growth_audit(owner_id,request_id,rules,earned_delta,applied_revision)
  values(u,p_request_id,p_rules,(delta->>'earned')::bigint,(result->>'revision')::bigint);
 delete from trainer_internal.growth_audit audit where audit.owner_id=u and audit.applied_revision<(result->>'revision')::bigint-100;
 return result;
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
 raise sqlstate 'PT422' using message='invalid_growth_input';
end $$;
