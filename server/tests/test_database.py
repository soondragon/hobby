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


@pytest.fixture(scope='module', autouse=True)
def schema():
    if not DSN:
        return
    with psycopg.connect(DSN, autocommit=True) as db:
        # Never run destructive fixtures on a remote or preexisting application DB.
        assert db.info.host in ('127.0.0.1', 'localhost') and db.info.dbname == 'trainer_test'
        db.execute("do $$ begin if not exists(select 1 from pg_roles where rolname='anon') then create role anon; end if; if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if; end $$")
        db.execute('create schema auth; create table auth.users(id uuid primary key); create table auth.identities(user_id uuid,provider text,provider_id text,identity_data jsonb)')
        db.execute("create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$")
        db.execute('grant usage on schema auth,public to anon,authenticated')
        for migration in sorted(Path('../supabase/migrations').glob('*.sql')):
            db.execute(migration.read_text())
        for uid, alias in [(A, 'trainer-a'), (B, 'trainer-b')]:
            db.execute('insert into auth.users values(%s)', (uid,))
            db.execute('insert into auth.identities values(%s,\'github\',%s,%s)', (uid, alias, Jsonb({'user_name': alias})))


def connect(uid=A):
    db = psycopg.connect(DSN, autocommit=True)
    db.execute('set role authenticated')
    db.execute("select set_config('request.jwt.claim.sub',%s,false)", (uid,))
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
        assert db.execute('select count(*) from public.trainer_saves').fetchone()[0] == 0
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
        write(db, 1, uuid4(), state)
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
