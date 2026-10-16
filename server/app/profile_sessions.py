"""Opaque application sessions; only one-way token digests enter PostgreSQL."""
import hashlib
import secrets
from fastapi import HTTPException
import psycopg
from psycopg.types.json import Jsonb
from .github_profile import GitHubProfile


def digest(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


class ProfileSessions:
    def __init__(self, pool):
        self.pool = pool

    async def call(self, function: str, arguments: tuple):
        # Function identifiers are a closed server-owned allow list, never request data.
        signatures = {'open_profile_session': '(%s,%s,%s,%s)',
                      'rotate_profile_session': '(%s,%s,%s)', 'profile_request': '(%s,%s,%s)',
                      'encounter_request': '(%s,%s,%s)', 'encounter_skill_request': '(%s,%s,%s)'}
        try:
            async with self.pool.connection(timeout=5) as connection:
                async with connection.transaction():
                    await connection.execute("set local statement_timeout = '10s'")
                    cursor = await connection.execute(f'select trainer_internal.{function}{signatures[function]}', arguments)
                    return (await cursor.fetchone())[0]
        except psycopg.Error as error:
            status, detail = {'42501': (401, 'authentication_required'), 'PT409': (409, 'save_conflict'),
                             'PT422': (422, 'invalid_save'), 'PT429': (429, 'growth_rate_limit')}.get(error.sqlstate, (503, 'storage_unavailable'))
            raise HTTPException(status, detail) from None
        except TimeoutError:
            raise HTTPException(503, 'storage_unavailable') from None

    async def issue(self, profile: GitHubProfile):
        access, refresh = 'hts_' + secrets.token_urlsafe(48), 'htr_' + secrets.token_urlsafe(48)
        user = await self.call('open_profile_session', (profile.github_id, profile.alias, digest(access), digest(refresh)))
        return dict(access_token=access, refresh_token=refresh, expires_in=900, user=user)

    async def refresh(self, token: str):
        access, refresh = 'hts_' + secrets.token_urlsafe(48), 'htr_' + secrets.token_urlsafe(48)
        user = await self.call('rotate_profile_session', (digest(token), digest(access), digest(refresh)))
        return dict(access_token=access, refresh_token=refresh, expires_in=900, user=user)

    async def request(self, token: str, action: str, command=None):
        if not token.startswith('hts_') or not 32 <= len(token) <= 256:
            raise HTTPException(401, 'authentication_required')
        return await self.call('profile_request', (digest(token), action, Jsonb(command) if command is not None else None))

    async def authenticate(self, token):
        return await self.request(token, 'user')

    async def read(self, token):
        return await self.request(token, 'read')

    async def write(self, token, command):
        result = await self.request(token, 'write', command.model_dump(mode='json', exclude_none=True))
        # Return the retry only after call() commits the durable admission.
        if result.get('error') == 'growth_rate_limit':
            delay = max(1, min(3600, int(result.get('retryAfter', 30))))
            raise HTTPException(429, 'growth_rate_limit', headers={'Retry-After': str(delay)})
        return result

    async def encounter(self, token, action, command=None):
        result = await self.call('encounter_request', (digest(token), action, Jsonb(command or {})))
        # Raise only after the transaction commits, preserving failed invitation attempt counters.
        if error := result.get('error'):
            status = {'rate_limited': 429, 'not_owned': 403, 'invalid_invitation': 404}.get(error, 409)
            raise HTTPException(status, error)
        return result

    async def skill(self, token, action, command):
        result = await self.call('encounter_skill_request', (digest(token), action, Jsonb(command)))
        if error := result.get('error'):
            raise HTTPException({'not_owned':403, 'illegal_move':422, 'cooldown':429}.get(error,409), error)
        return result
