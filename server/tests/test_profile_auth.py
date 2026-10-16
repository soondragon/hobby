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


def test_bundled_database_certificate_resolves_independently_of_working_directory(monkeypatch, tmp_path):
    from pathlib import Path
    from urllib.parse import urlsplit, parse_qs
    monkeypatch.setenv('GITHUB_PROFILE_CLIENT_ID', 'client')
    monkeypatch.setenv('GITHUB_PROFILE_CLIENT_SECRET', 'secret')
    monkeypatch.setenv('TRAINER_DATABASE_URL', 'postgresql://trainer_api:secret@example.com/postgres?sslmode=verify-full&sslrootcert=bundled')
    monkeypatch.chdir(tmp_path)
    config = ProfileConfiguration.from_environment()
    query = parse_qs(urlsplit(config.database_url).query)
    certificate = Path(query['sslrootcert'][0])
    assert certificate.is_absolute() and certificate.is_file()
    assert query['sslmode'] == ['verify-full']
    assert 'BEGIN CERTIFICATE' in certificate.read_text()
    from psycopg.conninfo import conninfo_to_dict
    assert conninfo_to_dict(config.database_url)['sslrootcert'] == str(certificate)


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


@pytest.mark.asyncio
@pytest.mark.parametrize('failure,status,detail', [
    ('incorrect_client_credentials',503,'github_authentication_configuration'),
    ('redirect_uri_mismatch',503,'github_authentication_configuration'),
    ('incorrect_code_verifier',401,'github_pkce_verification_failed'),
    ('bad_verification_code',401,'github_authentication_failed'),
    ('unknown_private_value',401,'github_authentication_failed')])
async def test_provider_errors_are_classified_without_exposing_response_secrets(failure,status,detail):
    async def handler(request):
        return httpx.Response(200,json={'error':failure,'error_description':'private-provider-description','access_token':'private-token'})
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        provider=GitHubProfileProvider(ProfileConfiguration('client','secret','unused'),client)
        with pytest.raises(HTTPException) as error: await provider.exchange('private-code','v'*43)
        assert error.value.status_code==status
        assert error.value.detail==detail
        assert 'private' not in error.value.detail
