-- Require ordered catalog routes and prevent banked-growth side channels.
create or replace function trainer_internal.check_transition(previous jsonb,candidate jsonb,old_rules jsonb,rules jsonb) returns jsonb
language plpgsql stable set search_path='' as $$
declare earned numeric; spend numeric; permitted numeric:=0; prior_ledger jsonb; next_ledger jsonb;
 ledger_key text; ledger_value jsonb; prior_mon jsonb; next_mon jsonb; old_entry jsonb; new_entry jsonb;
 growth numeric:=(rules->>'growthDifficulty')::numeric; shop numeric:=(rules->>'shopDifficulty')::numeric;
 prior_difficulty numeric:=(old_rules->>'growthDifficulty')::numeric;
 grant_limit integer:=0; grant_count integer:=0; candy_before numeric; candy_after numeric; candy_credit numeric;
 minimum_purchase numeric:=0; minted_mints numeric; mint_consumed numeric; charm_delta numeric;
 available_xp numeric; before_progress numeric; after_progress numeric; carry numeric;
 first_threshold numeric; rebased_profile jsonb;
 extra_mint_cost numeric:=0; tolerance numeric:=0; new_dex_count integer:=0; graduated boolean:=false; released boolean:=false; egg_cost numeric:=0;
begin
 perform public.validate_trainer_save(candidate);
 if growth is null or shop is null or growth<0.1 or growth>2 or shop<0.1 or shop>2
  or jsonb_typeof(rules)<>'object' or rules-array['growthDifficulty','shopDifficulty']<>'{}'::jsonb then
  raise sqlstate 'PT422' using message='invalid_rules'; end if;
 if previous is null or previous='null'::jsonb then
  if coalesce((candidate->>'usedSinceInstall')::numeric,0)<>0 or coalesce((candidate->>'spentTokens')::numeric,0)<>0
   or coalesce((candidate->>'eggUsage')::numeric,0)<>0 or coalesce(candidate->'active','null'::jsonb)<>'null'::jsonb
   or coalesce(candidate->'dex','[]'::jsonb)<>'[]'::jsonb or coalesce(candidate->'inventory','{}'::jsonb)<>'{}'::jsonb
   or coalesce(candidate->'collectedFinals','[]'::jsonb)<>'[]'::jsonb
   or candidate ? 'pendingHatchID' or candidate ? 'eggTier'
   or coalesce(candidate->'candyGrantTier','{}'::jsonb)<>'{}'::jsonb then
   raise sqlstate 'PT422' using message='initial_save_must_be_empty'; end if;
  return jsonb_build_object('earned',0,'rewards',0);
 end if;
 earned:=coalesce((candidate->>'usedSinceInstall')::numeric,0)-coalesce((previous->>'usedSinceInstall')::numeric,0);
 spend:=coalesce((candidate->>'spentTokens')::numeric,0)-coalesce((previous->>'spentTokens')::numeric,0);
 if earned<0 or spend<0 then raise sqlstate 'PT422' using message='counter_regression'; end if;
 prior_ledger:=nullif(previous->'claimedTodayTokensByProvider','null'::jsonb);
 next_ledger:=nullif(candidate->'claimedTodayTokensByProvider','null'::jsonb);
 if coalesce((previous->>'installBaselineSet')::boolean,false) and prior_ledger is not null then
  if next_ledger is null or not coalesce((candidate->>'installBaselineSet')::boolean,false) then
   raise sqlstate 'PT422' using message='baseline_removed'; end if;
  if coalesce(candidate->>'lastDate','')<coalesce(previous->>'lastDate','') then
   raise sqlstate 'PT422' using message='usage_date_regression'; end if;
  if candidate->>'lastDate'=previous->>'lastDate' then
   if exists(select 1 from jsonb_object_keys(prior_ledger) as prior_keys(provider_key) where not(next_ledger ? prior_keys.provider_key)) then
    raise sqlstate 'PT422' using message='provider_removed'; end if;
   for ledger_key,ledger_value in select * from jsonb_each(next_ledger) loop
    if prior_ledger ? ledger_key then permitted:=permitted+greatest(0,(ledger_value::text)::numeric-(prior_ledger->>ledger_key)::numeric); end if;
   end loop;
  else
   select coalesce(sum(value::numeric),0) into permitted from jsonb_each_text(next_ledger);
  end if;
 end if;
 if earned<>permitted then raise sqlstate 'PT422' using message='unbacked_token_credit'; end if;
 -- Calendar checks use the server clock in the transactional entry point, not caller dates.
 candy_before:=coalesce((previous->'inventory'->>'rareCandy')::numeric,0);
 candy_after:=coalesce((candidate->'inventory'->>'rareCandy')::numeric,0);
 if coalesce((previous->>'candyFeatureSeeded')::boolean,false) then
  for ledger_key,ledger_value in select * from jsonb_each(coalesce(candidate->'candyGrantTier','{}'::jsonb)) loop
   if ledger_value='1'::jsonb and (coalesce(previous->'candyGrantTier'->ledger_key,'0'::jsonb)<>'1'::jsonb
    or previous->'candyWindowEpoch'->ledger_key is distinct from candidate->'candyWindowEpoch'->ledger_key) then
     grant_limit:=grant_limit+case when lower(ledger_key) like '%sevenday%' or lower(ledger_key) like '%weekly%' then 5 else 1 end;
   end if;
  end loop;
 end if;
 -- Only observed inventory increases are treated as quota rewards; unseen grant-and-consume
 -- batches are rejected rather than manufacturing hidden candy XP.
 grant_count:=least(grant_limit,greatest(0,candy_after-candy_before)::integer);
 charm_delta:=coalesce((candidate->'inventory'->>'shinyCharm')::numeric,0)-coalesce((previous->'inventory'->>'shinyCharm')::numeric,0);
 if charm_delta<0 or coalesce((candidate->'inventory'->>'shinyCharm')::numeric,0)>1 then
  raise sqlstate 'PT422' using message='invalid_passive_item'; end if;
 minted_mints:=greatest(0,coalesce((candidate->'inventory'->>'mint')::numeric,0)-coalesce((previous->'inventory'->>'mint')::numeric,0));
 minimum_purchase:=charm_delta*round(3000000000*shop)+minted_mints*round(100000000*shop)
  +greatest(0,candy_after-candy_before-grant_count)*round(500000000*shop);
 prior_mon:=nullif(previous->'active','null'::jsonb); next_mon:=nullif(candidate->'active','null'::jsonb);
 if prior_mon is not null and next_mon is not null and prior_mon->'profile'->>'instanceID'=next_mon->'profile'->>'instanceID'
  and next_mon->'nature' is distinct from prior_mon->'nature'
  and coalesce((previous->'inventory'->>'mint')::numeric,0)-coalesce((candidate->'inventory'->>'mint')::numeric,0)<1 then
   extra_mint_cost:=round(100000000*shop); minimum_purchase:=minimum_purchase+extra_mint_cost;
 end if;
 if spend<minimum_purchase then raise sqlstate 'PT422' using message='unpaid_inventory'; end if;
 candy_credit:=greatest(0,candy_before-candy_after)+floor(greatest(0,spend-minimum_purchase)/round(500000000*shop));
 available_xp:=earned+candy_credit*100000000;
 prior_mon:=nullif(previous->'active','null'::jsonb); next_mon:=nullif(candidate->'active','null'::jsonb);
 if (next_mon is not null or prior_mon is not null) and coalesce((candidate->>'eggUsage')::numeric,0)<>0 then
  raise sqlstate 'PT422' using message='active_cannot_bank_egg_growth'; end if;
 if nullif(candidate->'eggTier','null'::jsonb) is not null and candidate->'eggTier' is distinct from previous->'eggTier' then
  if candidate->>'eggTier'='legendary' then raise sqlstate 'PT422' using message='unavailable_egg'; end if;
  egg_cost:=round(case candidate->>'eggTier' when 'uncommon' then 2500000000 when 'rare' then 4000000000 else 1000000000 end*shop);
  if spend-minimum_purchase<egg_cost then raise sqlstate 'PT422' using message='unpaid_egg'; end if;
 end if;
 -- Existing catches may acquire public metadata, but never a different identity or growth.
 for old_entry in select * from jsonb_array_elements(coalesce(previous->'dex','[]'::jsonb)) loop
  select value into new_entry from jsonb_array_elements(coalesce(candidate->'dex','[]'::jsonb)) where value->>'id'=old_entry->>'id';
  if not found or new_entry-array['names','namesVersion','profile'] is distinct from old_entry-array['names','namesVersion','profile'] then
   raise sqlstate 'PT422' using message='existing_catch_changed'; end if;
  if new_entry->'profile'->'growthTokens' is distinct from old_entry->'profile'->'growthTokens' or new_entry->'profile'->'level' is distinct from old_entry->'profile'->'level' then raise sqlstate 'PT422' using message='caught_growth_changed'; end if;
  perform trainer_internal.check_profile(old_entry->'profile',new_entry->'profile',old_entry->>'rarity',coalesce((old_entry->'profile'->>'growthTokens')::numeric,0));
 end loop;
 for new_entry in select value from jsonb_array_elements(coalesce(candidate->'dex','[]'::jsonb))
  where not exists(select 1 from jsonb_array_elements(coalesce(previous->'dex','[]'::jsonb)) as old_catches(entry) where old_catches.entry->>'id'=value->>'id') loop
  new_dex_count:=new_dex_count+1;
  if new_dex_count>1 or prior_mon is null or new_entry->>'id' is distinct from prior_mon->'profile'->>'instanceID'
   or new_entry->'baseID' is distinct from prior_mon->'baseID' or new_entry->'isShiny' is distinct from prior_mon->'isShiny'
   or new_entry->'rarity' is distinct from prior_mon->'rarity' then
   raise sqlstate 'PT422' using message='unearned_catch'; end if;
  released:=new_entry ? 'releasedAt'; graduated:=not released;
  if released then
   egg_cost:=round(case candidate->>'eggTier' when 'uncommon' then 2500000000 when 'rare' then 4000000000 else 1000000000 end*shop);
   if spend-minimum_purchase<egg_cost then raise sqlstate 'PT422' using message='unpaid_egg'; end if;
   perform trainer_internal.check_profile(prior_mon->'profile',new_entry->'profile',new_entry->>'rarity',coalesce((prior_mon->'profile'->>'growthTokens')::numeric,0));
  else
   if new_entry->'chainOrder' is distinct from prior_mon->'plannedPathIDs'
    or (new_entry->>'finalID')::int<>(prior_mon->'plannedPathIDs'->>-1)::int
    or trainer_internal.progress(prior_mon,prior_difficulty)+available_xp*(case when coalesce((prior_mon->>'hasGrowthBoost')::boolean,false) then 2 else 1 end)/growth+25<trainer_internal.rarity_total(prior_mon->>'rarity') then
    raise sqlstate 'PT422' using message='unearned_graduation'; end if;
   perform trainer_internal.check_profile(prior_mon->'profile',new_entry->'profile',new_entry->>'rarity',trainer_internal.rarity_total(new_entry->>'rarity'));
  end if;
 end loop;
 if egg_cost>0 then
  candy_credit:=greatest(0,candy_before-candy_after)+floor(greatest(0,spend-minimum_purchase-egg_cost)/round(500000000*shop));
  available_xp:=earned+candy_credit*100000000;
 end if;
 if prior_mon is not null and next_mon is not null and prior_mon->'profile'->>'instanceID'=next_mon->'profile'->>'instanceID'
  and nullif(prior_mon->'dittoDisguise','null'::jsonb) is not null
  and not coalesce((prior_mon->>'dittoRevealed')::boolean,false) and coalesce((next_mon->>'dittoRevealed')::boolean,false) then
  first_threshold:=round(round(round(trainer_internal.rarity_total(prior_mon->>'rarity')/((prior_mon->>'totalForms')::int*((prior_mon->>'totalForms')::int+1)/2)) /
    (case when coalesce((prior_mon->>'hasGrowthBoost')::boolean,false) then 2 else 1 end))*growth);
  if new_dex_count<>0 or (prior_mon->>'stageIndex')::int<>0
   or (prior_mon->>'usedAtStage')::numeric+available_xp<first_threshold
   or next_mon->>'baseID'<>'132' or next_mon->>'rarity'<>'rare'
   or next_mon->'plannedPathIDs'<>'[132]'::jsonb or next_mon->'pathIDs'<>'[132]'::jsonb
   or next_mon->>'stageIndex'<>'0' or next_mon->>'totalForms'<>'1'
   or next_mon-array['baseID','rarity','pathIDs','plannedPathIDs','stageIndex','totalForms','usedAtStage','profile','hasGrowthBoost','dittoRevealed']
     is distinct from prior_mon-array['baseID','rarity','pathIDs','plannedPathIDs','stageIndex','totalForms','usedAtStage','profile','hasGrowthBoost','dittoRevealed']
   or (next_mon->>'usedAtStage')::numeric>greatest(0,(prior_mon->>'usedAtStage')::numeric+available_xp-first_threshold)+2 then
   raise sqlstate 'PT422' using message='invalid_disguise_reveal'; end if;
  if coalesce((next_mon->>'hasGrowthBoost')::boolean,false) is distinct from exists(select 1 from jsonb_array_elements_text(coalesce(previous->'collectedFinals','[]'::jsonb)) as finals(key) where finals.key like '132:%') then
   raise sqlstate 'PT422' using message='unearned_repeat_boost'; end if;
  rebased_profile:=jsonb_set(prior_mon->'profile','{growthTokens}',to_jsonb(floor(least(1,(prior_mon->'profile'->>'growthTokens')::numeric/trainer_internal.rarity_total(prior_mon->>'rarity'))*3000000000)));
  perform trainer_internal.check_profile(rebased_profile,next_mon->'profile','rare',greatest((rebased_profile->>'growthTokens')::numeric,trainer_internal.progress(next_mon,growth,true)));
 elsif prior_mon is not null and next_mon is not null and prior_mon->'profile'->>'instanceID'=next_mon->'profile'->>'instanceID' then
  if new_dex_count<>0 or next_mon-array['usedAtStage','stageIndex','pathIDs','profile','nature']
   is distinct from prior_mon-array['usedAtStage','stageIndex','pathIDs','profile','nature'] then
   raise sqlstate 'PT422' using message='active_identity_changed'; end if;
  if (next_mon->>'stageIndex')::int<(prior_mon->>'stageIndex')::int
   or next_mon->'pathIDs' is distinct from (select jsonb_agg(value order by ordinality) from jsonb_array_elements(next_mon->'plannedPathIDs') with ordinality where ordinality<=(next_mon->>'stageIndex')::int+1) then
   raise sqlstate 'PT422' using message='invalid_evolution_path'; end if;
  before_progress:=trainer_internal.progress(prior_mon,prior_difficulty);
  after_progress:=trainer_internal.progress(next_mon,growth);
  tolerance:=case when prior_mon->'stageIndex' is distinct from next_mon->'stageIndex' or prior_difficulty<>growth then 25 else 0 end;
  if after_progress>before_progress+available_xp*(case when coalesce((next_mon->>'hasGrowthBoost')::boolean,false) then 2 else 1 end)/growth+tolerance then
   raise sqlstate 'PT422' using message='unearned_stage_growth'; end if;
  perform trainer_internal.check_profile(prior_mon->'profile',next_mon->'profile',next_mon->>'rarity',trainer_internal.progress(next_mon,growth,true));
  if next_mon->'nature' is distinct from prior_mon->'nature' then
   mint_consumed:=coalesce((previous->'inventory'->>'mint')::numeric,0)-coalesce((candidate->'inventory'->>'mint')::numeric,0);
   if mint_consumed<1 and extra_mint_cost=0 then raise sqlstate 'PT422' using message='unpaid_nature_change'; end if;
  end if;
 elsif next_mon is not null then
  if not exists(select 1 from trainer_internal.species_rules species where species.base_id=(next_mon->>'baseID')::int
   and species.rarity=next_mon->>'rarity' and exists(select 1 from jsonb_array_elements(species.paths) as paths(route) where paths.route=next_mon->'plannedPathIDs'))
   or (next_mon->>'totalForms')::int<>jsonb_array_length(next_mon->'plannedPathIDs')
   or nullif(next_mon->'profile','null'::jsonb) is null
   or next_mon->'pathIDs' is distinct from (select jsonb_agg(value order by ordinality) from jsonb_array_elements(next_mon->'plannedPathIDs') with ordinality where ordinality<=(next_mon->>'stageIndex')::int+1)
   or coalesce((next_mon->>'dittoRevealed')::boolean,false)
   or (nullif(next_mon->'dittoDisguise','null'::jsonb) is not null and
       (next_mon->'dittoDisguise'<>next_mon->'baseID' or next_mon->>'rarity'<>'common' or (next_mon->>'totalForms')::int<2)) then
   raise sqlstate 'PT422' using message='invalid_birth_species'; end if;
  if coalesce((next_mon->>'hasGrowthBoost')::boolean,false) is distinct from exists(select 1 from jsonb_array_elements_text(coalesce(previous->'collectedFinals','[]'::jsonb)) as finals(key) where finals.key like ((next_mon->>'baseID')||':%')) then
   raise sqlstate 'PT422' using message='unearned_repeat_boost'; end if;
  if prior_mon is not null and new_dex_count<>1 then raise sqlstate 'PT422' using message='individual_replaced'; end if;
  carry:=case when prior_mon is null then floor(coalesce((previous->>'eggUsage')::numeric,0)*growth/prior_difficulty) else 0 end+available_xp;
  if carry<round(5000000*growth) then raise sqlstate 'PT422' using message='unearned_hatch'; end if;
  after_progress:=trainer_internal.progress(next_mon,growth);
  if after_progress>greatest(0,carry-round(5000000*growth))*(case when coalesce((next_mon->>'hasGrowthBoost')::boolean,false) then 2 else 1 end)/growth+25 then raise sqlstate 'PT422' using message='unearned_birth_growth'; end if;
  perform trainer_internal.check_profile(null,next_mon->'profile',next_mon->>'rarity',trainer_internal.progress(next_mon,growth,true));
 elsif prior_mon is not null and new_dex_count<>1 then raise sqlstate 'PT422' using message='individual_removed';
 end if;
 if prior_mon is null and next_mon is null and coalesce((candidate->>'eggUsage')::numeric,0)>floor(coalesce((previous->>'eggUsage')::numeric,0)*growth/prior_difficulty)+available_xp then
  raise sqlstate 'PT422' using message='unearned_egg_growth'; end if;
 if not graduated and not(coalesce(candidate->'collectedFinals','[]'::jsonb) @> coalesce(previous->'collectedFinals','[]'::jsonb) and coalesce(previous->'collectedFinals','[]'::jsonb) @> coalesce(candidate->'collectedFinals','[]'::jsonb)) then
  raise sqlstate 'PT422' using message='unearned_completion'; end if;
 if graduated and exists(select 1 from jsonb_array_elements_text(coalesce(candidate->'collectedFinals','[]'::jsonb)) as finals(final_key)
  where not(coalesce(previous->'collectedFinals','[]'::jsonb) ? finals.final_key)
  and finals.final_key<>((prior_mon->>'baseID')||':'||(prior_mon->'plannedPathIDs'->>-1))) then
  raise sqlstate 'PT422' using message='unearned_completion'; end if;
 return jsonb_build_object('earned',earned,'rewards',grant_count);
end $$;
