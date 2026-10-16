import base64
import hashlib
import json
import httpx
import pytest
from fastapi import FastAPI, HTTPException
from app.release_routes import router
from app.profile_sessions import ProfileSessions
from app.models import SaveCommand
from uuid import uuid4


@pytest.mark.asyncio
async def test_public_feed_and_exact_download_without_account_access(tmp_path):
    content = b'public-application' * 100
    name = 'trainer-0.3.0-' + hashlib.sha256(content).hexdigest() + '.zip'
    (tmp_path / name).write_bytes(content)
    payload = dict(downloadURL='https://hobby-trainer.vercel.app/downloads/cloud/' + name, size=len(content))
    envelope = dict(payload=base64.b64encode(json.dumps(payload).encode()).decode(), signature='test-signature')
    (tmp_path/'latest.json').write_text(json.dumps(envelope))
    app = FastAPI(); app.include_router(router(tmp_path))
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app),base_url='http://test') as client:
        assert (await client.get('/api/app-release')).json() == envelope
        landing = await client.get('/app')
        assert landing.status_code == 200 and name in landing.text and 'v0.3.0' in landing.text
        response = await client.get('/downloads/cloud/'+name)
        assert response.status_code == 200 and response.content == content
        assert response.headers['content-type'] == 'application/zip'
        assert (await client.get('/downloads/cloud/private.env')).status_code == 404
    (tmp_path/name).write_bytes(b'wrong-size')
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app),base_url='http://test') as client:
        assert (await client.get('/api/app-release')).status_code == 503


@pytest.mark.asyncio
async def test_missing_manifest_fails_closed(tmp_path):
    app=FastAPI();app.include_router(router(tmp_path))
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app),base_url='http://test') as client:
        assert (await client.get('/api/app-release')).status_code==503


@pytest.mark.asyncio
async def test_growth_admission_retry_is_reported_after_committed_call():
    class Sessions(ProfileSessions):
        committed = False
        async def request(self, token, action, command=None):
            assert action == 'write'
            self.committed=True
            return dict(error='growth_rate_limit',retryAfter=150)
    sessions=Sessions(None)
    command=SaveCommand.model_validate(dict(schemaVersion=1,expectedRevision=1,requestID=uuid4(),operation='save',state={}))
    with pytest.raises(HTTPException) as error:
        await sessions.write('unused',command)
    assert sessions.committed and error.value.status_code==429
    assert error.value.headers['Retry-After']=='150'
