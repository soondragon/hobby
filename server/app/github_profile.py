"""No email endpoints or privileged scopes: accept a verified GitHub numeric ID and login only."""
from dataclasses import dataclass
import re
import httpx
from fastapi import HTTPException
from .profile_configuration import ProfileConfiguration


@dataclass(frozen=True, slots=True)
class GitHubProfile:
    github_id: str
    alias: str


class GitHubProfileProvider:
    def __init__(self, configuration: ProfileConfiguration, client: httpx.AsyncClient):
        self.configuration, self.client = configuration, client

    async def exchange(self, code: str, verifier: str) -> GitHubProfile:
        try:
            response = await self.client.post('https://github.com/login/oauth/access_token',
                headers={'Accept': 'application/json'}, data={
                    'client_id': self.configuration.client_id, 'client_secret': self.configuration.client_secret,
                    'code': code, 'code_verifier': verifier, 'redirect_uri': self.configuration.redirect_uri})
            body = response.json()
            # Return only allowlisted diagnostics, never provider descriptions or credentials.
            if isinstance(body,dict) and body.get('error'):
                if body['error'] in ('incorrect_client_credentials','redirect_uri_mismatch'):
                    raise HTTPException(503,'github_authentication_configuration')
                if body['error'] == 'incorrect_code_verifier':
                    raise HTTPException(401,'github_pkce_verification_failed')
                raise HTTPException(401,'github_authentication_failed')
            # Reject old grants that GitHub may silently carry over from a previous authorization.
            if not isinstance(body, dict) or response.status_code != 200 or body.get('error') or not body.get('access_token'):
                raise HTTPException(401, 'github_authentication_failed')
            if body.get('scope') != '' or body.get('token_type', '').lower() != 'bearer':
                raise HTTPException(403, 'github_public_profile_only')
            profile = await self.client.get('https://api.github.com/user', headers={
                'Authorization': f"Bearer {body['access_token']}", 'Accept': 'application/vnd.github+json'})
            # Check the effective scope independently of the token-exchange response.
            if profile.status_code != 200 or profile.headers.get('x-oauth-scopes') != '':
                raise HTTPException(403, 'github_public_profile_only')
            user = profile.json()
            if not isinstance(user, dict):
                raise HTTPException(401, 'github_authentication_failed')
            user_id, alias = user.get('id'), user.get('login')
            if type(user_id) is not int or user_id <= 0 or not isinstance(alias, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]{0,38}', alias):
                raise HTTPException(401, 'github_authentication_failed')
            return GitHubProfile(str(user_id), alias)
        except (httpx.HTTPError, ValueError, TypeError, KeyError):
            raise HTTPException(503, 'github_authentication_unavailable') from None
