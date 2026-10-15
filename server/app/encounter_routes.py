"""Participant-only display encounters; no growth changes or battle commands."""
from typing import Annotated, Literal
from uuid import UUID
from fastapi import APIRouter, Request, HTTPException
from pydantic import BaseModel, ConfigDict, Field, model_validator


class EncounterCommand(BaseModel):
    model_config = ConfigDict(extra='forbid', strict=True)
    action: Literal['create', 'join', 'read', 'select', 'leave']
    code: Annotated[str, Field(pattern=r'^[a-f0-9]{32}$')] | None = None
    roomID: Annotated[UUID, Field(strict=False)] | None = None
    expectedRevision: Annotated[int, Field(ge=1, le=9_000_000_000_000_000)] | None = None
    individualID: Annotated[str, Field(min_length=1, max_length=128, pattern=r'^[A-Za-z0-9_-]+$')] | None = None

    @model_validator(mode='after')
    def required_fields(self):
        required = {'create': set(), 'join': {'code'}, 'read': {'roomID'},
                    'select': {'roomID', 'expectedRevision', 'individualID'},
                    'leave': {'roomID', 'expectedRevision'}}[self.action]
        actual = {key for key in self.model_fields_set if key != 'action'}
        if actual != required or any(getattr(self, key) is None for key in required):
            raise ValueError('Invalid encounter command')
        return self


def router(authenticated_token):
    routes = APIRouter(prefix='/api/encounter')

    @routes.get('/roster')
    async def roster(request: Request):
        token = await authenticated_token(request)
        return await request.app.state.gateway.encounter(token, 'roster')

    @routes.post('')
    async def command(body: EncounterCommand, request: Request):
        if request.headers.get('content-type', '').split(';')[0] != 'application/json':
            raise HTTPException(415, 'json_required')
        token = await authenticated_token(request)
        return await request.app.state.gateway.encounter(token, body.action, body.model_dump(mode='json', exclude_none=True, exclude={'action'}))

    return routes
