"""Run only against the disposable local PostgreSQL test database."""
import os
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from uuid import uuid4
import psycopg
from psycopg.types.json import Jsonb
import pytest

DSN = os.environ.get('TRAINER_TEST_DATABASE_URL')
pytestmark = pytest.mark.skipif(not DSN, reason='Disposable DB not selected')
A, B = str(uuid4()), str(uuid4())
MIGRATION_OWNER = str(uuid4())


@pytest.fixture(scope='module', autouse=True)
def schema():
    if not DSN:
        return
    with psycopg.connect(DSN, autocommit=True) as db:
        # Never run destructive fixtures on a remote or preexisting application DB.
        assert db.info.host in ('127.0.0.1', 'localhost') and db.info.dbname == 'trainer_test'
        db.execute("do $$ begin if not exists(select 1 from pg_roles where rolname='anon') then create role anon; end if; if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if; end $$")
        db.execute('create schema auth; create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz); create table auth.users(id uuid primary key); create table auth.identities(user_id uuid,provider text,provider_id text,identity_data jsonb)')
        db.execute("create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$")
        db.execute("create function auth.jwt() returns jsonb language sql stable as $$ select jsonb_build_object('session_id',nullif(current_setting('request.jwt.claim.session_id',true),'')) $$")
        db.execute('grant usage on schema auth,public to anon,authenticated')
        for migration in sorted(Path('../supabase/migrations').glob('*.sql')):
            if migration.name.endswith('_public_profile_auth.sql'):
                # Populate the OLD schema before migration, preserving an actual existing save.
                db.execute('insert into auth.users values(%s)', (MIGRATION_OWNER,))
                db.execute("insert into auth.identities values(%s,'github','991120',%s)",
                           (MIGRATION_OWNER, Jsonb({'user_name': 'pre-migration'})))
                db.execute("select set_config('request.jwt.claim.sub',%s,false)", (MIGRATION_OWNER,))
                db.execute('select trainer_internal.write_snapshot(%s,%s,%s,%s)',
                           (0, uuid4(), 'save', Jsonb(baseline())))
            db.execute(migration.read_text())
        for uid, alias in [(A, 'trainer-a'), (B, 'trainer-b')]:
            db.execute('insert into auth.users values(%s)', (uid,))
            db.execute('insert into auth.sessions(id,user_id) values(%s,%s)', (uid,uid))
            db.execute('insert into auth.identities values(%s,\'github\',%s,%s)', (uid, alias, Jsonb({'user_name': alias})))


def connect(uid=A):
    db = psycopg.connect(DSN, autocommit=True)
    db.execute('set role authenticated')
    db.execute("select set_config('request.jwt.claim.sub',%s,false)", (uid,))
    db.execute("select set_config('request.jwt.claim.session_id',%s,false)", (uid,))
    return db


def write(db, revision, request_id, state=None, operation='save'):
    return db.execute('select public.write_trainer_save(%s,%s,%s,%s)', (revision, request_id, operation, Jsonb(state or {}))).fetchone()[0]


def test_owner_isolation_idempotency_conflicts_and_rollback():
    request_id = uuid4()
    with connect() as db:
        assert write(db, 0, request_id)['revision'] == 1
        assert write(db, 0, request_id)['revision'] == 1
        with pytest.raises(psycopg.Error) as error:
            write(db, 0, request_id, {'language': 'ko'})
        assert error.value.sqlstate == 'PT409'
        with pytest.raises(psycopg.Error):
            db.execute('delete from public.trainer_saves')
        with pytest.raises(psycopg.Error) as error:
            write(db, 1, uuid4(), operation='migrate')
        assert error.value.sqlstate == 'PT422'
    with connect(B) as db:
        with pytest.raises(psycopg.Error):
            db.execute('select count(*) from public.trainer_saves')
        result = db.execute('select public.read_trainer_save()').fetchone()[0]
        assert result['revision'] == 0 and result['ownerID'] == B
    with psycopg.connect(DSN, autocommit=True) as db:
        db.execute('set role anon')
        with pytest.raises(psycopg.Error):
            db.execute('select public.read_trainer_save()')


def test_concurrent_cas_only_one_winner():
    with connect(B) as db:
        write(db, 0, uuid4())
    def save(_):
        with connect(B) as db:
            try:
                return write(db, 1, uuid4())['revision']
            except psycopg.Error as error:
                return error.sqlstate
    with ThreadPoolExecutor(max_workers=2) as executor:
        assert sorted(map(str, executor.map(save, range(2)))) == ['2', 'PT409']


def test_normalized_roundtrip_preserves_uint64_and_order():
    state = {'installBaselineSet': True, 'lastDate': '2026-10-15',
             'claimedTodayTokensByProvider': {'provider': 0},
             'usedSinceInstall': 4, 'spentTokens': 1, 'inventory': {'mint': 2},
             'candyGrantTier': {'provider': 1}, 'candyWindowEpoch': {'provider': 'day'},
             'dex': [{'id': 'individual-1', 'baseID': 1, 'finalID': 3, 'isShiny': True,
                      'chainOrder': [1,2,3], 'rarity': 'common', 'profile': {'instanceID':'individual-1', 'seed': 18446744073709551615, 'ivs':{key:31 for key in ['hp','attack','defense','specialAttack','specialDefense','speed']},'abilityIsHidden':False,'level':5,'growthTokens':0,'moves':[]}}]}
    with connect() as db:
        # Codec fidelity uses an operator-owned legacy fixture, not a user-authorized write.
        db.execute('reset role')
        db.execute('select trainer_internal.write_snapshot(%s,%s,%s,%s)', (1, uuid4(), 'save', Jsonb(state)))
        db.execute('set role authenticated')
        result = db.execute('select public.read_trainer_save()').fetchone()[0]['state']
        assert result == state
        with pytest.raises(psycopg.Error):
            write(db, 2, uuid4(), {'inventory': {'mint': -1}})
        assert db.execute('select public.read_trainer_save()').fetchone()[0]['revision'] == 2


def test_real_usage_baseline_shape_and_ledger_limits():
    with psycopg.connect(DSN, autocommit=True) as db:
        db.execute('select public.validate_trainer_save(%s)', (Jsonb({
            'installBaselineSet': True, 'lastDate': '2026-10-15',
            'claimedTodayTokensByProvider': {'provider': 123}}),))
        with pytest.raises(psycopg.Error) as error:
            db.execute('select public.validate_trainer_save(%s)', (Jsonb({
                'claimedTodayTokensByProvider': {'x' * 257: 1}}),))
        assert error.value.sqlstate == 'PT422'


def seed_player(state):
    """Operator-owned fixture; the application role cannot invoke this raw writer."""
    uid = str(uuid4())
    with psycopg.connect(DSN, autocommit=True) as db:
        db.execute('insert into auth.users values(%s)', (uid,))
        db.execute('insert into auth.sessions(id,user_id) values(%s,%s)', (uid,uid))
        db.execute('insert into auth.identities values(%s,\'github\',%s,%s)', (uid, uid, Jsonb({'user_name': 'test-player'})))
        db.execute("select set_config('request.jwt.claim.sub',%s,false)", (uid,))
        db.execute('select trainer_internal.write_snapshot(%s,%s,%s,%s)', (0, uuid4(), 'save', Jsonb(state)))
    return uid


def baseline():
    from datetime import datetime, timezone
    return {'installBaselineSet': True, 'lastDate': datetime.now(timezone.utc).date().isoformat(),
            'claimedTodayTokensByProvider': {'provider': 1000}, 'usedSinceInstall': 0,
            'spentTokens': 0, 'eggUsage': 0, 'inventory': {}, 'dex': [], 'collectedFinals': []}


def active_state():
    state = baseline()
    state['active'] = {'baseID': 1, 'pathIDs': [1], 'plannedPathIDs': [1,2,3], 'stageIndex': 0,
        'usedAtStage': 0, 'rarity': 'common', 'totalForms': 3, 'isShiny': False, 'nature': 'hardy',
        'hasGrowthBoost': False, 'profile': {'instanceID': 'test-individual', 'seed': 18446744073709551615,
        'ivs': {key: 15 for key in ['hp','attack','defense','specialAttack','specialDefense','speed']},
        'abilityIsHidden': False, 'level': 5, 'growthTokens': 0, 'moves': []}}
    return state


def assert_rejected(previous, candidate, code='PT422'):
    uid = seed_player(previous)
    with connect(uid) as db:
        with pytest.raises(psycopg.Error) as error:
            write(db, 1, uuid4(), candidate)
        assert error.value.sqlstate == code
        assert db.execute('select public.read_trainer_save()').fetchone()[0]['revision'] == 1


def test_growth_accepts_exact_token_delta_and_retries_without_double_debit():
    import copy
    previous = baseline()
    uid = seed_player(previous)
    candidate = copy.deepcopy(previous)
    candidate['claimedTodayTokensByProvider']['provider'] += 123
    candidate['usedSinceInstall'] += 123
    candidate['eggUsage'] += 123
    request_id = uuid4()
    with connect(uid) as db:
        assert write(db, 1, request_id, candidate)['revision'] == 2
        assert write(db, 1, request_id, candidate)['revision'] == 2
        with pytest.raises(psycopg.Error):
            db.execute('select trainer_internal.write_snapshot(%s,%s,%s,%s)', (2, uuid4(), 'save', Jsonb(candidate)))
    with psycopg.connect(DSN) as db:
        assert db.execute('select count(*) from trainer_internal.growth_audit where owner_id=%s', (uid,)).fetchone()[0] == 1


def test_growth_rejects_unbacked_wallet_egg_item_and_initial_catch():
    import copy
    for field in ['usedSinceInstall', 'eggUsage']:
        previous = baseline(); candidate = copy.deepcopy(previous); candidate[field] += 1
        assert_rejected(previous, candidate)
    previous = baseline(); candidate = copy.deepcopy(previous); candidate['inventory'] = {'mint': 1}
    assert_rejected(previous, candidate)
    previous = baseline(); candidate = copy.deepcopy(previous); candidate['collectedFinals'] = ['1:3']
    assert_rejected(previous, candidate)
    with connect(B) as db:
        # A role cannot use a private implementation to bypass the public policy.
        with pytest.raises(psycopg.Error):
            db.execute('select trainer_internal.write_snapshot(%s,%s,%s,%s)', (2, uuid4(), 'save', Jsonb({})))


def test_growth_rejects_rate_spike_even_with_matching_forged_provider_ledger():
    previous = baseline(); candidate = baseline()
    candidate['claimedTodayTokensByProvider']['provider'] += 25000001
    candidate['usedSinceInstall'] = 25000001; candidate['eggUsage'] = 25000001
    assert_rejected(previous, candidate, 'PT429')


@pytest.mark.parametrize('mutation', ['level','xp','stage','seed','ivs','shiny','nature','replace'])
def test_existing_individual_cannot_be_forged(mutation):
    import copy
    previous = active_state(); candidate = copy.deepcopy(previous); mon = candidate['active']
    if mutation == 'level': mon['profile']['level'] = 100
    elif mutation == 'xp': mon['profile']['growthTokens'] = 750000000
    elif mutation == 'stage': mon['pathIDs'] = [1,2,3]; mon['stageIndex'] = 2
    elif mutation == 'seed': mon['profile']['seed'] = 1
    elif mutation == 'ivs': mon['profile']['ivs']['hp'] = 31
    elif mutation == 'shiny': mon['isShiny'] = True
    elif mutation == 'nature': mon['nature'] = 'adamant'
    elif mutation == 'replace': mon['profile']['instanceID'] = 'forged-individual'
    assert_rejected(previous, candidate)


def test_growth_valid_active_delta_and_paid_mint_preserve_original_rules():
    import copy
    previous = active_state(); previous['inventory'] = {'mint': 1}
    uid = seed_player(previous); candidate = copy.deepcopy(previous)
    candidate['claimedTodayTokensByProvider']['provider'] += 100
    candidate['usedSinceInstall'] = 100
    candidate['active']['usedAtStage'] = 100
    candidate['active']['profile']['growthTokens'] = 100
    candidate['active']['nature'] = 'adamant'; candidate['inventory'] = {'mint': 0}
    with connect(uid) as db:
        assert write(db, 1, uuid4(), candidate)['revision'] == 2


def test_server_checks_graduation_and_preserves_completed_collection():
    import copy
    previous = active_state(); mon = previous['active']
    mon.update({'pathIDs': [1,2,3], 'stageIndex': 2, 'usedAtStage': 374999900})
    mon['profile'].update({'growthTokens': 749999900, 'level': 99})
    uid = seed_player(previous); candidate = copy.deepcopy(previous)
    candidate['claimedTodayTokensByProvider']['provider'] += 100; candidate['usedSinceInstall'] = 100
    candidate['active'] = None
    profile = copy.deepcopy(mon['profile']); profile.update({'growthTokens': 750000000, 'level': 100})
    candidate['dex'] = [{'id': profile['instanceID'], 'baseID': 1, 'finalID': 3, 'chainOrder': [1,2,3],
        'rarity':'common','isShiny':False,'nature':'hardy','profile': profile}]
    candidate['collectedFinals'] = ['1:3']
    with connect(uid) as db:
        assert write(db, 1, uuid4(), candidate)['revision'] == 2
        forged = copy.deepcopy(candidate); forged['dex'][0]['profile']['seed'] = 2
        with pytest.raises(psycopg.Error): write(db, 2, uuid4(), forged)


def test_revoked_session_cannot_read_or_write_even_with_valid_user_claim():
    uid = seed_player(baseline())
    with psycopg.connect(DSN, autocommit=True) as db:
        db.execute('delete from auth.sessions where user_id=%s', (uid,))
    with connect(uid) as db:
        with pytest.raises(psycopg.Error) as error:
            db.execute('select public.read_trainer_save()')
        assert error.value.sqlstate == '42501'
        with pytest.raises(psycopg.Error):
            write(db, 1, uuid4(), baseline())


def test_hatching_accepts_canonical_species_and_rejects_forged_rarity_boost_and_path():
    import copy
    previous = baseline(); previous['eggUsage'] = 4999999
    candidate = active_state(); candidate['eggUsage'] = 0
    candidate['claimedTodayTokensByProvider']['provider'] += 1; candidate['usedSinceInstall'] = 1
    # Bulbasaur is rare (capture rate 45), not the synthetic common test fixture.
    candidate['active']['rarity'] = 'rare'
    uid = seed_player(previous)
    with connect(uid) as db:
        assert write(db, 1, uuid4(), candidate)['revision'] == 2
    for field, value in [('rarity','common'), ('hasGrowthBoost',True), ('plannedPathIDs',[1,3])]:
        forged = copy.deepcopy(candidate); forged['active'][field] = value
        if field == 'plannedPathIDs': forged['active']['totalForms'] = len(value)
        assert_rejected(previous, forged)


def test_paid_mint_cannot_also_buy_candy_growth():
    import copy
    previous = active_state(); previous['usedSinceInstall'] = 500000000
    candidate = copy.deepcopy(previous); candidate['spentTokens'] = 500000000
    candidate['active']['nature'] = 'adamant'
    candidate['active']['usedAtStage'] = 100000000
    candidate['active']['profile'].update(growthTokens=100000000,level=17)
    assert_rejected(previous, candidate)


def test_graduation_cannot_assume_unearned_repeat_boost():
    import copy
    previous = active_state(); mon=previous['active']
    mon.update(pathIDs=[1,2,3],stageIndex=2,usedAtStage=374999800)
    mon['profile'].update(growthTokens=749999800,level=99)
    candidate=copy.deepcopy(previous);candidate['active']=None
    candidate['claimedTodayTokensByProvider']['provider']+=100;candidate['usedSinceInstall']=100
    profile=copy.deepcopy(mon['profile']);profile.update(growthTokens=750000000,level=100)
    candidate['dex']=[dict(id=profile['instanceID'],baseID=1,finalID=3,chainOrder=[1,2,3],rarity='common',isShiny=False,nature='hardy',profile=profile)]
    candidate['collectedFinals']=['1:3']
    assert_rejected(previous,candidate)


def test_ditto_reveal_preserves_individual_and_fraction_without_mint():
    import copy
    previous=active_state();mon=previous['active'];mon.update(dittoDisguise=1,dittoRevealed=False,usedAtStage=125000000)
    mon['profile'].update(growthTokens=125000000,level=20)
    candidate=copy.deepcopy(previous);mon=candidate['active']
    mon.update(baseID=132,pathIDs=[132],plannedPathIDs=[132],totalForms=1,stageIndex=0,usedAtStage=0,rarity='rare',dittoRevealed=True)
    mon['profile'].update(growthTokens=500000000,level=20)
    uid=seed_player(previous)
    with connect(uid) as db:assert write(db,1,uuid4(),candidate)['revision']==2
    forged=copy.deepcopy(candidate);forged['active']['profile']['seed']=1
    assert_rejected(previous,forged)


def test_rules_change_preserves_egg_fraction_and_remote_rules_roundtrip():
    previous=baseline();previous['eggUsage']=1000000
    uid=seed_player(previous);candidate=baseline();candidate['eggUsage']=2000000
    rules=dict(growthDifficulty=2,shopDifficulty=0.5)
    with connect(uid) as db:
        result=db.execute('select public.write_trainer_save(%s,%s,%s,%s,%s)',(1,uuid4(),'save',Jsonb(candidate),Jsonb(rules))).fetchone()[0]
        assert result['revision']==2
        loaded=db.execute('select public.read_trainer_save()').fetchone()[0]
        assert loaded['rules']==rules
        assert loaded['state']['eggUsage']==2000000


def test_active_cannot_hide_growth_in_future_egg_or_buy_free_premium_egg():
    import copy
    previous=active_state();candidate=copy.deepcopy(previous);candidate['eggUsage']=1000000000
    assert_rejected(previous,candidate)
    previous=baseline();candidate=copy.deepcopy(previous);candidate['eggTier']='rare'
    assert_rejected(previous,candidate)


@pytest.mark.asyncio
async def test_email_free_login_preserves_legacy_save_alias_rename_and_session_isolation():
    """HTTP -> mock GitHub public identity -> real least-privilege PostgreSQL -> existing save."""
    import httpx
    from psycopg_pool import AsyncConnectionPool
    from app.github_profile import GitHubProfileProvider
    from app.profile_configuration import ProfileConfiguration
    from app.profile_sessions import ProfileSessions
    from app.main import create_app
    uid=MIGRATION_OWNER
    current_identity=[991120,'renamed-user'];requests=[]
    async def github(request):
        requests.append(request.url.path)
        if request.url.host=='github.com':
            return httpx.Response(200,json=dict(access_token='github-public-only',token_type='bearer',scope=''))
        return httpx.Response(200,headers={'X-OAuth-Scopes':''},json=dict(id=current_identity[0],login=current_identity[1]))
    async def restrict(connection):
        await connection.execute('set role trainer_api');await connection.commit()
    async with AsyncConnectionPool(DSN,min_size=1,max_size=2,configure=restrict,open=False) as pool:
        async with httpx.AsyncClient(transport=httpx.MockTransport(github)) as upstream:
            sessions=ProfileSessions(pool)
            provider=GitHubProfileProvider(ProfileConfiguration('client','server-only','unused'),upstream)
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=create_app(sessions,provider)),base_url='http://test') as client:
                async def login():
                    result=await client.post('/api/auth/github/exchange',json={'code':'one-time-code','verifier':'v'*43})
                    assert result.status_code==200,result.text
                    return result.json()
                first=await login();assert first['user']==dict(id=uid,alias='renamed-user')
                headers={'Authorization':'Bearer '+first['access_token']}
                loaded=(await client.get('/api/companion',headers=headers)).json()
                assert loaded['revision']==1 and loaded['ownerID']==uid and loaded['alias']=='renamed-user'
                assert loaded['state']['claimedTodayTokensByProvider']==baseline()['claimedTodayTokensByProvider']
                assert 'email' not in first and 'email' not in first['user']
                command=dict(schemaVersion=1,expectedRevision=1,requestID=str(uuid4()),operation='save',state=loaded['state'])
                assert (await client.put('/api/companion',headers=headers,json=command)).status_code==200
                current_identity[:]=[991123,'other-user']
                second=await login();foreign_headers={'Authorization':'Bearer '+second['access_token']}
                other=(await client.get('/api/companion',headers=foreign_headers)).json()
                assert other['revision']==0 and other['ownerID']!=uid
                command['ownerID']=uid
                assert (await client.put('/api/companion',headers=foreign_headers,json=command)).status_code==422
                assert (await client.get('/api/companion?alias=renamed-user',headers=foreign_headers)).status_code==400
                import asyncio
                interleaved = await asyncio.gather(*[
                    client.get('/api/companion',headers=headers if i%2==0 else foreign_headers) for i in range(20)])
                assert all(result.status_code==200 and result.json()['ownerID']==(uid if i%2==0 else other['ownerID'])
                           for i,result in enumerate(interleaved))
                rotations=await asyncio.gather(*[client.post('/api/auth/refresh',json={'refresh_token':first['refresh_token']}) for _ in range(2)])
                assert sorted(result.status_code for result in rotations)==[200,401]
                refresh=next(result for result in rotations if result.status_code==200)
                assert (await client.get('/api/companion',headers=headers)).status_code==401
                assert (await client.post('/api/auth/refresh',json={'refresh_token':first['refresh_token']})).status_code==401
                renewed={'Authorization':'Bearer '+refresh.json()['access_token']}
                assert (await client.get('/api/companion',headers=renewed)).json()['revision']==2
                assert (await client.post('/api/auth/logout',headers=renewed)).status_code==204
                assert (await client.get('/api/companion',headers=renewed)).status_code==401
                assert (await client.post('/api/auth/refresh',json={'refresh_token':refresh.json()['refresh_token']})).status_code==401
                assert (await client.get('/api/companion',headers=foreign_headers)).status_code==200
                assert (await client.get('/api/companion',headers={'Authorization':'Bearer old-supabase-jwt'})).status_code==401
                with psycopg.connect(DSN,autocommit=True) as operator:
                    operator.execute("update trainer_internal.profile_sessions set access_until=clock_timestamp()-interval '1 second',refresh_until=clock_timestamp()-interval '1 second' where owner_id=%s",(other['ownerID'],))
                assert (await client.get('/api/companion',headers=foreign_headers)).status_code==401
                assert (await client.post('/api/auth/refresh',json={'refresh_token':second['refresh_token']})).status_code==401
                async with pool.connection() as connection:
                    for table in ['public.trainer_saves','trainer_internal.profile_sessions']:
                        with pytest.raises(psycopg.Error):await connection.execute('select * from '+table)
                        await connection.rollback()
    assert requests==['/login/oauth/access_token','/user']*2
    with psycopg.connect(DSN) as db:
        hashes=db.execute('select access_hash,refresh_hash from trainer_internal.profile_sessions').fetchall()
        assert hashes and all(len(a)==len(r)==64 for a,r in hashes)
        assert all(first['access_token'] not in row for row in hashes)
