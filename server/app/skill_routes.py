"""Validated visual skill events. No damage, player-stat edits or reward endpoints."""
from typing import Annotated
from uuid import UUID
from fastapi import APIRouter, Request, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from .move_catalog import move_details, species_moves


class SkillCommand(BaseModel):
    model_config = ConfigDict(extra='forbid', strict=True)
    roomID: Annotated[UUID, Field(strict=False)]
    expectedRevision: Annotated[int, Field(ge=1, le=9_000_000_000_000_000)]
    requestID: Annotated[UUID, Field(strict=False)]
    moveID: Annotated[int, Field(ge=1, le=559)]


def router(authenticated_token):
    routes = APIRouter()

    @routes.get('/api/pokedex/{species_id}/moves')
    async def pokedex(species_id: int):
        result = species_moves(species_id)
        if result is None: raise HTTPException(404, 'species_not_supported')
        return result

    @routes.get('/api/encounter/{room_id}/moves')
    async def moves(room_id: UUID, request: Request):
        token = await authenticated_token(request)
        result = await request.app.state.gateway.skill(token, 'moves', dict(roomID=str(room_id)))
        return dict(moves=move_details(result['moveIDs']), versionGroup='black-2-white-2')

    @routes.post('/api/encounter/attack')
    async def attack(body: SkillCommand, request: Request):
        token = await authenticated_token(request)
        return await request.app.state.gateway.skill(token, 'attack', body.model_dump(mode='json'))

    return routes
