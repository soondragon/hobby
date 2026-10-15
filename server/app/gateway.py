from dataclasses import dataclass
from uuid import UUID
import httpx
from fastapi import HTTPException
from .configuration import Configuration
from .models import SaveCommand


@dataclass(frozen=True, slots=True)
class AuthenticatedUser:
    user_id: UUID


class SupabaseGateway:
    def __init__(self, configuration: Configuration, client: httpx.AsyncClient):
        self.configuration = configuration
        self.client = client

    def headers(self, token: str) -> dict[str, str]:
        return {"apikey": self.configuration.publishable_key, "Authorization": f"Bearer {token}",
                "Accept": "application/json", "Content-Type": "application/json"}

    async def authenticate(self, token: str) -> AuthenticatedUser:
        try:
            response = await self.client.get(f"{self.configuration.supabase_url}/auth/v1/user", headers=self.headers(token))
        except httpx.HTTPError:
            raise HTTPException(503, "authentication_unavailable") from None
        if response.status_code in (401, 403):
            raise HTTPException(401, "authentication_required")
        if response.status_code == 429:
            raise HTTPException(429, "try_later")
        if response.status_code != 200:
            raise HTTPException(503, "authentication_unavailable")
        try:
            body = response.json()
            identities = body.get("identities") or []
            if not any(identity.get("provider") == "github" for identity in identities):
                raise ValueError("GitHub identity required")
            return AuthenticatedUser(UUID(body["id"]))
        except (ValueError, KeyError, TypeError):
            raise HTTPException(401, "authentication_required") from None

    async def _rpc(self, token: str, name: str, body: dict):
        try:
            response = await self.client.post(f"{self.configuration.supabase_url}/rest/v1/rpc/{name}",
                                              headers=self.headers(token), json=body)
        except httpx.HTTPError:
            raise HTTPException(503, "storage_unavailable") from None
        if response.status_code >= 400:
            try:
                code = response.json().get("code")
            except ValueError:
                code = None
            if code in ("PT409", "23505"):
                raise HTTPException(409, "save_conflict")
            if code == "PT429":
                raise HTTPException(429, "growth_rate_limit")
            if code == "PT422":
                raise HTTPException(422, "invalid_save")
            if response.status_code in (401, 403):
                raise HTTPException(401, "authentication_required")
            raise HTTPException(503, "storage_unavailable")
        try:
            return response.json()
        except ValueError:
            raise HTTPException(503, "storage_unavailable") from None

    async def read(self, token: str):
        return await self._rpc(token, "read_trainer_save", {})

    async def write(self, token: str, command: SaveCommand):
        return await self._rpc(token, "write_trainer_save", {
            "p_expected_revision": command.expectedRevision, "p_request_id": str(command.requestID),
            "p_operation": command.operation, "p_state": command.state.model_dump(mode="json", exclude_none=True),
            "p_rules": command.rules.model_dump(mode="json"),
        })
