-- The public API never exposes the snapshot writer or validator-bypassing helpers.
create schema trainer_internal;
revoke all on schema trainer_internal from public, anon, authenticated;
grant usage on schema trainer_internal to authenticated;
alter function public.write_trainer_save(bigint,uuid,text,jsonb) set schema trainer_internal;
alter function trainer_internal.write_trainer_save(bigint,uuid,text,jsonb) rename to write_snapshot;
revoke all on function trainer_internal.write_snapshot(bigint,uuid,text,jsonb) from public,anon,authenticated;
alter function public.read_trainer_save() set schema trainer_internal;
alter function trainer_internal.read_trainer_save() rename to read_snapshot;
revoke all on function trainer_internal.read_snapshot() from public,anon,authenticated;

create table trainer_internal.species_rules(base_id integer primary key, rarity text not null, paths jsonb not null);
alter table trainer_internal.species_rules enable row level security;
revoke all on trainer_internal.species_rules from public,anon,authenticated;
insert into trainer_internal.species_rules(base_id,rarity,paths) values
(1,'rare','[[1,2,3]]'::jsonb),
(4,'rare','[[4,5,6]]'::jsonb),
(7,'rare','[[7,8,9]]'::jsonb),
(10,'common','[[10,11,12]]'::jsonb),
(13,'common','[[13,14,15]]'::jsonb),
(16,'common','[[16,17,18]]'::jsonb),
(19,'common','[[19,20]]'::jsonb),
(21,'common','[[21,22]]'::jsonb),
(23,'common','[[23,24]]'::jsonb),
(27,'common','[[27,28]]'::jsonb),
(29,'common','[[29,30,31]]'::jsonb),
(32,'common','[[32,33,34]]'::jsonb),
(37,'common','[[37,38]]'::jsonb),
(41,'common','[[41,42,169]]'::jsonb),
(43,'common','[[43,44,45],[43,44,182]]'::jsonb),
(46,'common','[[46,47]]'::jsonb),
(48,'common','[[48,49]]'::jsonb),
(50,'common','[[50,51]]'::jsonb),
(52,'common','[[52,53],[52,863]]'::jsonb),
(54,'common','[[54,55]]'::jsonb),
(56,'common','[[56,57,979]]'::jsonb),
(58,'common','[[58,59]]'::jsonb),
(60,'common','[[60,61,62],[60,61,186]]'::jsonb),
(63,'common','[[63,64,65]]'::jsonb),
(66,'common','[[66,67,68]]'::jsonb),
(69,'common','[[69,70,71]]'::jsonb),
(72,'common','[[72,73]]'::jsonb),
(74,'common','[[74,75,76]]'::jsonb),
(77,'common','[[77,78]]'::jsonb),
(79,'common','[[79,80],[79,199]]'::jsonb),
(81,'common','[[81,82,462]]'::jsonb),
(83,'rare','[[83,865]]'::jsonb),
(84,'common','[[84,85]]'::jsonb),
(86,'common','[[86,87]]'::jsonb),
(88,'common','[[88,89]]'::jsonb),
(90,'common','[[90,91]]'::jsonb),
(92,'common','[[92,93,94]]'::jsonb),
(95,'rare','[[95,208]]'::jsonb),
(96,'common','[[96,97]]'::jsonb),
(98,'common','[[98,99]]'::jsonb),
(100,'common','[[100,101]]'::jsonb),
(102,'uncommon','[[102,103]]'::jsonb),
(104,'common','[[104,105]]'::jsonb),
(108,'rare','[[108,463]]'::jsonb),
(109,'common','[[109,110]]'::jsonb),
(111,'uncommon','[[111,112,464]]'::jsonb),
(114,'rare','[[114,465]]'::jsonb),
(115,'rare','[[115]]'::jsonb),
(116,'common','[[116,117,230]]'::jsonb),
(118,'common','[[118,119]]'::jsonb),
(120,'common','[[120,121]]'::jsonb),
(123,'rare','[[123,212],[123,900]]'::jsonb),
(127,'rare','[[127]]'::jsonb),
(128,'rare','[[128]]'::jsonb),
(129,'common','[[129,130]]'::jsonb),
(131,'rare','[[131]]'::jsonb),
(132,'rare','[[132]]'::jsonb),
(133,'rare','[[133,134],[133,135],[133,136],[133,196],[133,197],[133,470],[133,471],[133,700]]'::jsonb),
(137,'rare','[[137,233,474]]'::jsonb),
(138,'rare','[[138,139]]'::jsonb),
(140,'rare','[[140,141]]'::jsonb),
(142,'rare','[[142]]'::jsonb),
(144,'legendary','[[144]]'::jsonb),
(145,'legendary','[[145]]'::jsonb),
(146,'legendary','[[146]]'::jsonb),
(147,'rare','[[147,148,149]]'::jsonb),
(150,'legendary','[[150]]'::jsonb),
(151,'legendary','[[151]]'::jsonb),
(152,'rare','[[152,153,154]]'::jsonb),
(155,'rare','[[155,156,157]]'::jsonb),
(158,'rare','[[158,159,160]]'::jsonb),
(161,'common','[[161,162]]'::jsonb),
(163,'common','[[163,164]]'::jsonb),
(165,'common','[[165,166]]'::jsonb),
(167,'common','[[167,168]]'::jsonb),
(170,'common','[[170,171]]'::jsonb),
(172,'common','[[172,25,26]]'::jsonb),
(173,'common','[[173,35,36]]'::jsonb),
(174,'common','[[174,39,40]]'::jsonb),
(175,'common','[[175,176,468]]'::jsonb),
(177,'common','[[177,178]]'::jsonb),
(179,'common','[[179,180,181]]'::jsonb),
(187,'common','[[187,188,189]]'::jsonb),
(190,'rare','[[190,424]]'::jsonb),
(191,'common','[[191,192]]'::jsonb),
(193,'uncommon','[[193,469]]'::jsonb),
(194,'common','[[194,195],[194,980]]'::jsonb),
(198,'rare','[[198,430]]'::jsonb),
(200,'rare','[[200,429]]'::jsonb),
(201,'common','[[201]]'::jsonb),
(203,'uncommon','[[203,981]]'::jsonb),
(204,'common','[[204,205]]'::jsonb),
(206,'common','[[206,982]]'::jsonb),
(207,'uncommon','[[207,472]]'::jsonb),
(209,'common','[[209,210]]'::jsonb),
(211,'rare','[[211,904]]'::jsonb),
(213,'common','[[213]]'::jsonb),
(214,'rare','[[214]]'::jsonb),
(215,'uncommon','[[215,461],[215,903]]'::jsonb),
(216,'uncommon','[[216,217,901]]'::jsonb),
(218,'common','[[218,219]]'::jsonb),
(220,'common','[[220,221,473]]'::jsonb),
(222,'uncommon','[[222,864]]'::jsonb),
(223,'common','[[223,224]]'::jsonb),
(225,'rare','[[225]]'::jsonb),
(227,'rare','[[227]]'::jsonb),
(228,'uncommon','[[228,229]]'::jsonb),
(231,'uncommon','[[231,232]]'::jsonb),
(234,'rare','[[234,899]]'::jsonb),
(235,'rare','[[235]]'::jsonb),
(236,'uncommon','[[236,106],[236,107],[236,237]]'::jsonb),
(238,'rare','[[238,124]]'::jsonb),
(239,'rare','[[239,125,466]]'::jsonb),
(240,'rare','[[240,126,467]]'::jsonb),
(241,'rare','[[241]]'::jsonb),
(243,'legendary','[[243]]'::jsonb),
(244,'legendary','[[244]]'::jsonb),
(245,'legendary','[[245]]'::jsonb),
(246,'rare','[[246,247,248]]'::jsonb),
(249,'legendary','[[249]]'::jsonb),
(250,'legendary','[[250]]'::jsonb),
(251,'legendary','[[251]]'::jsonb),
(252,'rare','[[252,253,254]]'::jsonb),
(255,'rare','[[255,256,257]]'::jsonb),
(258,'rare','[[258,259,260]]'::jsonb),
(261,'common','[[261,262]]'::jsonb),
(263,'common','[[263,264,862]]'::jsonb),
(265,'common','[[265,266,267],[265,268,269]]'::jsonb),
(270,'common','[[270,271,272]]'::jsonb),
(273,'common','[[273,274,275]]'::jsonb),
(276,'common','[[276,277]]'::jsonb),
(278,'common','[[278,279]]'::jsonb),
(280,'common','[[280,281,282],[280,281,475]]'::jsonb),
(283,'common','[[283,284]]'::jsonb),
(285,'common','[[285,286]]'::jsonb),
(287,'common','[[287,288,289]]'::jsonb),
(290,'common','[[290,291],[290,292]]'::jsonb),
(293,'common','[[293,294,295]]'::jsonb),
(296,'common','[[296,297]]'::jsonb),
(298,'common','[[298,183,184]]'::jsonb),
(299,'common','[[299,476]]'::jsonb),
(300,'common','[[300,301]]'::jsonb),
(302,'rare','[[302]]'::jsonb),
(303,'rare','[[303]]'::jsonb),
(304,'common','[[304,305,306]]'::jsonb),
(307,'common','[[307,308]]'::jsonb),
(309,'uncommon','[[309,310]]'::jsonb),
(311,'common','[[311]]'::jsonb),
(312,'common','[[312]]'::jsonb),
(313,'common','[[313]]'::jsonb),
(314,'common','[[314]]'::jsonb),
(316,'common','[[316,317]]'::jsonb),
(318,'common','[[318,319]]'::jsonb),
(320,'common','[[320,321]]'::jsonb),
(322,'common','[[322,323]]'::jsonb),
(324,'uncommon','[[324]]'::jsonb),
(325,'common','[[325,326]]'::jsonb),
(327,'common','[[327]]'::jsonb),
(328,'common','[[328,329,330]]'::jsonb),
(331,'common','[[331,332]]'::jsonb),
(333,'common','[[333,334]]'::jsonb),
(335,'uncommon','[[335]]'::jsonb),
(336,'uncommon','[[336]]'::jsonb),
(337,'rare','[[337]]'::jsonb),
(338,'rare','[[338]]'::jsonb),
(339,'common','[[339,340]]'::jsonb),
(341,'common','[[341,342]]'::jsonb),
(343,'common','[[343,344]]'::jsonb),
(345,'rare','[[345,346]]'::jsonb),
(347,'rare','[[347,348]]'::jsonb),
(349,'common','[[349,350]]'::jsonb),
(351,'rare','[[351]]'::jsonb),
(352,'common','[[352]]'::jsonb),
(353,'common','[[353,354]]'::jsonb),
(355,'common','[[355,356,477]]'::jsonb),
(357,'common','[[357]]'::jsonb),
(359,'rare','[[359]]'::jsonb),
(360,'common','[[360,202]]'::jsonb),
(361,'common','[[361,362],[361,478]]'::jsonb),
(363,'common','[[363,364,365]]'::jsonb),
(366,'common','[[366,367],[366,368]]'::jsonb),
(369,'rare','[[369]]'::jsonb),
(370,'common','[[370]]'::jsonb),
(371,'rare','[[371,372,373]]'::jsonb),
(374,'rare','[[374,375,376]]'::jsonb),
(377,'legendary','[[377]]'::jsonb),
(378,'legendary','[[378]]'::jsonb),
(379,'legendary','[[379]]'::jsonb),
(380,'legendary','[[380]]'::jsonb),
(381,'legendary','[[381]]'::jsonb),
(382,'legendary','[[382]]'::jsonb),
(383,'legendary','[[383]]'::jsonb),
(384,'legendary','[[384]]'::jsonb),
(385,'legendary','[[385]]'::jsonb),
(386,'legendary','[[386]]'::jsonb),
(387,'rare','[[387,388,389]]'::jsonb),
(390,'rare','[[390,391,392]]'::jsonb),
(393,'rare','[[393,394,395]]'::jsonb),
(396,'common','[[396,397,398]]'::jsonb),
(399,'common','[[399,400]]'::jsonb),
(401,'common','[[401,402]]'::jsonb),
(403,'common','[[403,404,405]]'::jsonb),
(406,'common','[[406,315,407]]'::jsonb),
(408,'rare','[[408,409]]'::jsonb),
(410,'rare','[[410,411]]'::jsonb),
(412,'uncommon','[[412,413],[412,414]]'::jsonb),
(415,'uncommon','[[415,416]]'::jsonb),
(417,'common','[[417]]'::jsonb),
(418,'common','[[418,419]]'::jsonb),
(420,'common','[[420,421]]'::jsonb),
(422,'common','[[422,423]]'::jsonb),
(425,'common','[[425,426]]'::jsonb),
(427,'common','[[427,428]]'::jsonb),
(431,'common','[[431,432]]'::jsonb),
(433,'uncommon','[[433,358]]'::jsonb),
(434,'common','[[434,435]]'::jsonb),
(436,'common','[[436,437]]'::jsonb),
(438,'common','[[438,185]]'::jsonb),
(439,'common','[[439,122,866]]'::jsonb),
(440,'common','[[440,113,242]]'::jsonb),
(441,'rare','[[441]]'::jsonb),
(442,'uncommon','[[442]]'::jsonb),
(443,'rare','[[443,444,445]]'::jsonb),
(446,'uncommon','[[446,143]]'::jsonb),
(447,'uncommon','[[447,448]]'::jsonb),
(449,'common','[[449,450]]'::jsonb),
(451,'uncommon','[[451,452]]'::jsonb),
(453,'common','[[453,454]]'::jsonb),
(455,'common','[[455]]'::jsonb),
(456,'common','[[456,457]]'::jsonb),
(458,'rare','[[458,226]]'::jsonb),
(459,'uncommon','[[459,460]]'::jsonb),
(479,'rare','[[479]]'::jsonb),
(480,'legendary','[[480]]'::jsonb),
(481,'legendary','[[481]]'::jsonb),
(482,'legendary','[[482]]'::jsonb),
(483,'legendary','[[483]]'::jsonb),
(484,'legendary','[[484]]'::jsonb),
(485,'legendary','[[485]]'::jsonb),
(486,'legendary','[[486]]'::jsonb),
(487,'legendary','[[487]]'::jsonb),
(488,'legendary','[[488]]'::jsonb),
(489,'legendary','[[489]]'::jsonb),
(490,'legendary','[[490]]'::jsonb),
(491,'legendary','[[491]]'::jsonb),
(492,'legendary','[[492]]'::jsonb),
(493,'legendary','[[493]]'::jsonb),
(494,'legendary','[[494]]'::jsonb),
(495,'rare','[[495,496,497]]'::jsonb),
(498,'rare','[[498,499,500]]'::jsonb),
(501,'rare','[[501,502,503]]'::jsonb),
(504,'common','[[504,505]]'::jsonb),
(506,'common','[[506,507,508]]'::jsonb),
(509,'common','[[509,510]]'::jsonb),
(511,'common','[[511,512]]'::jsonb),
(513,'common','[[513,514]]'::jsonb),
(515,'common','[[515,516]]'::jsonb),
(517,'common','[[517,518]]'::jsonb),
(519,'common','[[519,520,521]]'::jsonb),
(522,'common','[[522,523]]'::jsonb),
(524,'common','[[524,525,526]]'::jsonb),
(527,'common','[[527,528]]'::jsonb),
(529,'uncommon','[[529,530]]'::jsonb),
(531,'common','[[531]]'::jsonb),
(532,'common','[[532,533,534]]'::jsonb),
(535,'common','[[535,536,537]]'::jsonb),
(538,'rare','[[538]]'::jsonb),
(539,'rare','[[539]]'::jsonb),
(540,'common','[[540,541,542]]'::jsonb),
(543,'common','[[543,544,545]]'::jsonb),
(546,'common','[[546,547]]'::jsonb),
(548,'common','[[548,549]]'::jsonb),
(550,'rare','[[550,902]]'::jsonb),
(551,'common','[[551,552,553]]'::jsonb),
(554,'uncommon','[[554,555]]'::jsonb),
(556,'common','[[556]]'::jsonb),
(557,'common','[[557,558]]'::jsonb),
(559,'common','[[559,560]]'::jsonb),
(561,'rare','[[561]]'::jsonb),
(562,'common','[[562,563],[562,867]]'::jsonb),
(564,'rare','[[564,565]]'::jsonb),
(566,'rare','[[566,567]]'::jsonb),
(568,'common','[[568,569]]'::jsonb),
(570,'uncommon','[[570,571]]'::jsonb),
(572,'common','[[572,573]]'::jsonb),
(574,'common','[[574,575,576]]'::jsonb),
(577,'common','[[577,578,579]]'::jsonb),
(580,'common','[[580,581]]'::jsonb),
(582,'common','[[582,583,584]]'::jsonb),
(585,'common','[[585,586]]'::jsonb),
(587,'common','[[587]]'::jsonb),
(588,'common','[[588,589]]'::jsonb),
(590,'common','[[590,591]]'::jsonb),
(592,'common','[[592,593]]'::jsonb),
(594,'uncommon','[[594]]'::jsonb),
(595,'common','[[595,596]]'::jsonb),
(597,'common','[[597,598]]'::jsonb),
(599,'common','[[599,600,601]]'::jsonb),
(602,'common','[[602,603,604]]'::jsonb),
(605,'common','[[605,606]]'::jsonb),
(607,'common','[[607,608,609]]'::jsonb),
(610,'uncommon','[[610,611,612]]'::jsonb),
(613,'uncommon','[[613,614]]'::jsonb),
(615,'rare','[[615]]'::jsonb),
(616,'common','[[616,617]]'::jsonb),
(618,'uncommon','[[618]]'::jsonb),
(619,'common','[[619,620]]'::jsonb),
(621,'rare','[[621]]'::jsonb),
(622,'common','[[622,623]]'::jsonb),
(624,'uncommon','[[624,625,983]]'::jsonb),
(626,'rare','[[626]]'::jsonb),
(627,'common','[[627,628]]'::jsonb),
(629,'common','[[629,630]]'::jsonb),
(631,'uncommon','[[631]]'::jsonb),
(632,'uncommon','[[632]]'::jsonb),
(633,'rare','[[633,634,635]]'::jsonb),
(636,'rare','[[636,637]]'::jsonb),
(638,'legendary','[[638]]'::jsonb),
(639,'legendary','[[639]]'::jsonb),
(640,'legendary','[[640]]'::jsonb),
(641,'legendary','[[641]]'::jsonb),
(642,'legendary','[[642]]'::jsonb),
(643,'legendary','[[643]]'::jsonb),
(644,'legendary','[[644]]'::jsonb),
(645,'legendary','[[645]]'::jsonb),
(646,'legendary','[[646]]'::jsonb),
(647,'legendary','[[647]]'::jsonb),
(648,'legendary','[[648]]'::jsonb),
(649,'legendary','[[649]]'::jsonb);

create table trainer_internal.growth_policy (
 owner_id uuid primary key references auth.users(id) on delete cascade,
 rules jsonb not null default '{"growthDifficulty":1,"shopDifficulty":1}',
 token_credit numeric not null default 25000000 check(token_credit between 0 and 25000000),
 refilled_at timestamptz not null default clock_timestamp(),
 reward_day date not null default current_date,
 rewards_today integer not null default 0 check(rewards_today between 0 and 30)
);
create table trainer_internal.growth_audit (
 owner_id uuid not null references auth.users(id) on delete cascade,
 request_id uuid not null,
 rules jsonb not null,
 earned_delta bigint not null,
 applied_revision bigint not null,
 accepted_at timestamptz not null default clock_timestamp(),
 primary key(owner_id,request_id)
);
alter table trainer_internal.growth_policy enable row level security;
alter table trainer_internal.growth_audit enable row level security;
revoke all on trainer_internal.growth_policy,trainer_internal.growth_audit from public,anon,authenticated;

create function trainer_internal.check_session() returns void
language plpgsql security definer set search_path='' as $$
declare session_uuid uuid; caller uuid:=auth.uid();
begin
 if caller is null then raise insufficient_privilege; end if;
 begin session_uuid:=(auth.jwt()->>'session_id')::uuid;
 exception when invalid_text_representation then raise insufficient_privilege; end;
 if session_uuid is null or not exists(select 1 from auth.sessions sessions
  where sessions.id=session_uuid and sessions.user_id=caller
  and (sessions.not_after is null or sessions.not_after>clock_timestamp())) then
  raise insufficient_privilege;
 end if;
end $$;

create function trainer_internal.read_owned_save() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform trainer_internal.check_session();
 return trainer_internal.read_snapshot();
end $$;

create function trainer_internal.rarity_total(rarity text) returns numeric
language sql immutable set search_path='' as $$
 select case rarity when 'common' then 750000000 when 'uncommon' then 1875000000
 when 'rare' then 3000000000 when 'legendary' then 6000000000 else null end::numeric
$$;

create function trainer_internal.progress(mon jsonb,difficulty numeric,clamp_phase boolean default false) returns numeric
language plpgsql immutable set search_path='' as $$
declare forms integer; stage integer; total numeric; completed numeric:=0; phase numeric; raw numeric; boost integer;
begin
 if mon is null or mon='null'::jsonb then return 0; end if;
 forms:=(mon->>'totalForms')::integer; stage:=(mon->>'stageIndex')::integer;
 total:=trainer_internal.rarity_total(mon->>'rarity');
 if forms<1 or forms>10 or stage<0 or stage>=forms or total is null then
  raise sqlstate 'PT422' using message='invalid_growth_shape'; end if;
 for i in 0..stage loop
  phase:=round(total*(i+1)/(forms*(forms+1)/2));
  if i<stage then completed:=completed+phase; end if;
 end loop;
 boost:=case when coalesce((mon->>'hasGrowthBoost')::boolean,false) then 2 else 1 end;
 raw:=coalesce((mon->>'usedAtStage')::numeric,0)*boost/difficulty;
 if clamp_phase then raw:=least(raw,phase); end if;
 return completed+raw;
end $$;

create function trainer_internal.check_profile(previous jsonb,next_profile jsonb,rarity text,maximum_growth numeric) returns void
language plpgsql immutable set search_path='' as $$
declare earned numeric; expected_level integer; previous_level integer; prior_growth numeric;
begin
 if next_profile is null or next_profile='null'::jsonb then
  if previous is not null and previous<>'null'::jsonb then raise sqlstate 'PT422' using message='profile_removed'; end if;
  return;
 end if;
 if previous is not null and previous<>'null'::jsonb then
  if next_profile->'instanceID' is distinct from previous->'instanceID'
   or next_profile->'seed' is distinct from previous->'seed'
   or next_profile->'ivs' is distinct from previous->'ivs' then
   raise sqlstate 'PT422' using message='individual_identity_changed';
  end if;
 end if;
 prior_growth:=coalesce((previous->>'growthTokens')::numeric,0);
 previous_level:=coalesce((previous->>'level')::int,5);
 earned:=(next_profile->>'growthTokens')::numeric;
 if earned<prior_growth or earned>greatest(prior_growth,least(trainer_internal.rarity_total(rarity),maximum_growth))+2 then
  raise sqlstate 'PT422' using message='unearned_profile_growth'; end if;
 expected_level:=greatest(previous_level,least(100,5+floor(95*least(1,earned/trainer_internal.rarity_total(rarity)))::int));
 if (next_profile->>'level')::int<>expected_level then raise sqlstate 'PT422' using message='invalid_level'; end if;
end $$;

create function trainer_internal.check_transition(previous jsonb,candidate jsonb,old_rules jsonb,rules jsonb) returns jsonb
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
   and species.rarity=next_mon->>'rarity' and species.paths @> jsonb_build_array(next_mon->'plannedPathIDs'))
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
  carry:=case when prior_mon is null then coalesce((previous->>'eggUsage')::numeric,0) else 0 end+available_xp;
  if carry<round(5000000*growth) then raise sqlstate 'PT422' using message='unearned_hatch'; end if;
  after_progress:=trainer_internal.progress(next_mon,growth);
  if after_progress>greatest(0,carry-round(5000000*growth))*(case when coalesce((next_mon->>'hasGrowthBoost')::boolean,false) then 2 else 1 end)/growth+25 then raise sqlstate 'PT422' using message='unearned_birth_growth'; end if;
  perform trainer_internal.check_profile(null,next_mon->'profile',next_mon->>'rarity',trainer_internal.progress(next_mon,growth,true));
 elsif prior_mon is not null and new_dex_count<>1 then raise sqlstate 'PT422' using message='individual_removed';
 end if;
 if prior_mon is null and next_mon is null and coalesce((candidate->>'eggUsage')::numeric,0)>coalesce((previous->>'eggUsage')::numeric,0)+earned then
  raise sqlstate 'PT422' using message='unearned_egg_growth'; end if;
 if not graduated and not(coalesce(candidate->'collectedFinals','[]'::jsonb) @> coalesce(previous->'collectedFinals','[]'::jsonb) and coalesce(previous->'collectedFinals','[]'::jsonb) @> coalesce(candidate->'collectedFinals','[]'::jsonb)) then
  raise sqlstate 'PT422' using message='unearned_completion'; end if;
 if graduated and exists(select 1 from jsonb_array_elements_text(coalesce(candidate->'collectedFinals','[]'::jsonb)) as finals(final_key)
  where not(coalesce(previous->'collectedFinals','[]'::jsonb) ? finals.final_key)
  and finals.final_key<>((prior_mon->>'baseID')||':'||(prior_mon->'plannedPathIDs'->>-1))) then
  raise sqlstate 'PT422' using message='unearned_completion'; end if;
 return jsonb_build_object('earned',earned,'rewards',grant_count);
end $$;

create function trainer_internal.write_trainer_save(p_expected_revision bigint,p_request_id uuid,p_operation text,p_state jsonb,
 p_rules jsonb default '{"growthDifficulty":1,"shopDifficulty":1}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid; previous jsonb; policy trainer_internal.growth_policy; result jsonb; delta jsonb;
 available_credit numeric; instant timestamptz:=clock_timestamp(); old_rules jsonb; prior_audit trainer_internal.growth_audit;
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
 if (delta->>'earned')::numeric>available_credit then raise sqlstate 'PT429' using message='growth_rate_limit'; end if;
 if (case when policy.reward_day=instant::date then policy.rewards_today else 0 end)+(delta->>'rewards')::integer>30 then
  raise sqlstate 'PT429' using message='reward_rate_limit'; end if;
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

create function public.read_trainer_save() returns jsonb language sql security invoker set search_path='' as $$
 select trainer_internal.read_owned_save()
$$;
create function public.write_trainer_save(p_expected_revision bigint,p_request_id uuid,p_operation text,p_state jsonb,
 p_rules jsonb default '{"growthDifficulty":1,"shopDifficulty":1}') returns jsonb
language sql security invoker set search_path='' as $$
 select trainer_internal.write_trainer_save(p_expected_revision,p_request_id,p_operation,p_state,p_rules)
$$;
-- Read helper performs auth.uid/GitHub checks. Internal writer is the guarded entry point;
-- write_snapshot is deliberately NOT granted, even to authenticated.
grant execute on function trainer_internal.read_owned_save() to authenticated;
revoke all on all functions in schema trainer_internal from public,anon;
revoke all on function trainer_internal.check_session(),trainer_internal.rarity_total(text),trainer_internal.progress(jsonb,numeric,boolean),
 trainer_internal.check_profile(jsonb,jsonb,text,numeric),trainer_internal.check_transition(jsonb,jsonb,jsonb,jsonb) from authenticated;
grant execute on function trainer_internal.write_trainer_save(bigint,uuid,text,jsonb,jsonb) to authenticated;
revoke all on function public.read_trainer_save(),public.write_trainer_save(bigint,uuid,text,jsonb,jsonb) from public,anon;
grant execute on function public.read_trainer_save(),public.write_trainer_save(bigint,uuid,text,jsonb,jsonb) to authenticated;

-- The application needs RPCs only. Direct table reads are closed, including stale tokens.
revoke select on public.trainer_profiles,public.trainer_saves,public.trainer_collection,
 public.trainer_inventory,public.trainer_candy_ledger,public.trainer_save_operations from authenticated;
