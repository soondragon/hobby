import json
from uuid import uuid4
import httpx
import pytest
from fastapi import HTTPException
from app.main import create_app
from app.models import CompanionSave
from app.configuration import Configuration
from app.gateway import SupabaseGateway


class Gateway:
    writes = 0
    async def authenticate(self, token):
        if token != 'valid':
            raise HTTPException(401, 'authentication_required')
    async def read(self, token):
        return {'revision': 0, 'state': None}
    async def write(self, token, command):
        self.writes += 1
        return {'revision': 1, 'requestID': str(command.requestID)}


@pytest.fixture
async def client():
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=create_app(Gateway())), base_url='http://test') as value:
        yield value


@pytest.mark.asyncio
async def test_auth_and_no_cache(client):
    assert (await client.get('/api/companion')).status_code == 401
    response = await client.get('/api/companion', headers={'Authorization': 'Bearer valid'})
    assert response.status_code == 200
    assert 'no-store' in response.headers['Cache-Control']
    assert (await client.get('/api/companion?alias=victim', headers={'Authorization': 'Bearer valid'})).status_code == 400


@pytest.mark.asyncio
@pytest.mark.parametrize('state', [{'spentTokens': 1}, {'usedSinceInstall': True}, {'dex': [{'id': 'bad'}]},
                                  {'ownerID': str(uuid4())}, {'active': {'baseID': -1}}, {'inventory': {'unknown': 1}}])
async def test_reject_invalid_private_payload(client, state):
    response = await client.put('/api/companion', headers={'Authorization': 'Bearer valid'}, json={
        'schemaVersion': 1, 'expectedRevision': 0, 'requestID': str(uuid4()), 'operation': 'save', 'state': state})
    assert response.status_code == 422
    assert response.json() == {'detail': 'invalid_save'}


@pytest.mark.asyncio
async def test_size_and_precision(client):
    response = await client.put('/api/companion', headers={'Authorization': 'Bearer valid', 'Content-Type': 'application/json'}, content=' ' * 1048577)
    assert response.status_code == 413
    response = await client.put('/api/companion', headers={'Authorization': 'Bearer valid'}, json={
        'schemaVersion': 1, 'expectedRevision': 0, 'requestID': str(uuid4()), 'operation': 'save', 'state': {}})
    assert response.status_code == 200
    response = await client.put('/api/companion', headers={'Authorization': 'Bearer valid'}, json={
        'schemaVersion': 1, 'expectedRevision': 0, 'requestID': str(uuid4()), 'operation': 'migrate', 'state': {}})
    assert response.status_code == 422


def test_database_schema_cannot_silently_drift_from_api_model():
    from pathlib import Path
    import re
    migration = Path('../supabase/migrations/202610150003_server_only_saves.sql').read_text()
    schemas = re.findall(r'\$schema\$(.*?)\$schema\$', migration, flags=re.S)
    assert schemas
    assert all(json.loads(schema) == CompanionSave.model_json_schema() for schema in schemas)


@pytest.mark.asyncio
async def test_gateway_forwards_same_user_token_and_masks_errors():
    seen = []
    async def handler(request):
        seen.append(request)
        if request.url.path.endswith('/user'):
            return httpx.Response(200, json={'id': str(uuid4()), 'identities': [{'provider': 'github'}]})
        return httpx.Response(409, json={'code': 'PT409', 'message': 'PRIVATE_PAYLOAD'})
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        gateway = SupabaseGateway(Configuration('https://example.supabase.co', 'sb_publishable_test'), client)
        await gateway.authenticate('user-token')
        with pytest.raises(HTTPException) as error:
            await gateway.read('user-token')
        assert error.value.status_code == 409
        assert error.value.detail == 'save_conflict'
        assert all(request.headers['Authorization'] == 'Bearer user-token' for request in seen)
