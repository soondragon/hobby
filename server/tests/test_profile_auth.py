import httpx
import pytest
from fastapi import HTTPException
from app.github_profile import GitHubProfileProvider
from app.profile_configuration import ProfileConfiguration
from app.main import create_app


@pytest.mark.asyncio
@pytest.mark.parametrize('exchange_scope,profile_scope', [('', ''), ('user:email',''), ('repo',''), ('','user:email'), (None,'')])
async def test_only_empty_effective_scopes_and_public_identity_are_accepted(exchange_scope,profile_scope):
    seen=[]
    async def handler(request):
        seen.append(request)
        if request.url.host=='github.com':
            return httpx.Response(200,json=dict(access_token='private-github-token',token_type='bearer',scope=exchange_scope))
        assert request.url.path=='/user'
        return httpx.Response(200,headers={'X-OAuth-Scopes':profile_scope},json=dict(id=123,login='test-user',email='ignored@example.invalid'))
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        provider=GitHubProfileProvider(ProfileConfiguration('client','server-secret','unused'),client)
        if exchange_scope==profile_scope=='':
            profile=await provider.exchange('code','v'*43)
            assert profile.github_id=='123' and profile.alias=='test-user'
            assert not hasattr(profile,'email') and len(seen)==2
            assert b'code_verifier=' in seen[0].content
        else:
            with pytest.raises(HTTPException) as error: await provider.exchange('code','v'*43)
            assert error.value.status_code==403
        assert not any('emails' in request.url.path for request in seen)


@pytest.mark.asyncio
async def test_auth_routes_bound_bodies_and_do_not_echo_credentials():
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=create_app(object())),base_url='http://test') as client:
        response=await client.post('/api/auth/github/exchange',json={'code':'private-credential','verifier':'short'})
        assert response.status_code==422 and 'private-credential' not in response.text
        response=await client.post('/api/auth/github/exchange',content=b' '*8193,headers={'Content-Type':'application/json'})
        assert response.status_code==413 and 'no-store' in response.headers['Cache-Control']
        response=await client.post('/api/auth/refresh',json={'refresh_token':'old-supabase-token'})
        assert response.status_code==422


def test_backend_configuration_never_accepts_administrator_database_role(monkeypatch):
    monkeypatch.setenv('GITHUB_PROFILE_CLIENT_ID','client');monkeypatch.setenv('GITHUB_PROFILE_CLIENT_SECRET','secret')
    for url in ['postgresql://postgres:secret@example.com/postgres?sslmode=verify-full',
                'postgresql://trainer_api:secret@example.com/postgres?sslmode=require']:
        monkeypatch.setenv('TRAINER_DATABASE_URL',url)
        with pytest.raises(ValueError): ProfileConfiguration.from_environment()
    monkeypatch.setenv('TRAINER_DATABASE_URL','postgresql://trainer_api:secret@example.com/postgres?sslmode=verify-full')
    assert ProfileConfiguration.from_environment().client_id=='client'


@pytest.mark.asyncio
@pytest.mark.parametrize('profile_json', [{'id':True,'login':'valid'},{'id':123,'login':'bad/name'},[],{'id':123}])
async def test_profile_identity_is_strict_and_upstream_errors_are_private(profile_json):
    async def handler(request):
        if request.url.host=='github.com':
            return httpx.Response(200,json=dict(access_token='secret-token',token_type='bearer',scope=''))
        return httpx.Response(200,headers={'X-OAuth-Scopes':''},json=profile_json)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        provider=GitHubProfileProvider(ProfileConfiguration('client','secret','unused'),client)
        with pytest.raises(HTTPException) as error:await provider.exchange('private-code','v'*43)
        assert error.value.status_code==401
        assert 'secret-token' not in error.value.detail and 'private-code' not in error.value.detail
