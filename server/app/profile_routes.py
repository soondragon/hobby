"""Email-free authentication routes; no caller-controlled redirect or identity fields."""
from typing import Annotated
from fastapi import APIRouter, HTTPException, Request, Response
from pydantic import BaseModel, ConfigDict, Field


class Exchange(BaseModel):
    model_config = ConfigDict(extra='forbid', strict=True)
    code: Annotated[str, Field(min_length=1, max_length=512, pattern=r'^[A-Za-z0-9_-]+$')]
    verifier: Annotated[str, Field(min_length=43, max_length=128, pattern=r'^[A-Za-z0-9._~-]+$')]


class Refresh(BaseModel):
    model_config = ConfigDict(extra='forbid', strict=True)
    refresh_token: Annotated[str, Field(min_length=32, max_length=256, pattern=r'^htr_[A-Za-z0-9_-]+$')]


def router(authenticated_token):
    routes = APIRouter(prefix='/api/auth')

    @routes.post('/github/exchange')
    async def exchange(body: Exchange, request: Request):
        if request.url.query:
            raise HTTPException(400, 'query_parameters_not_supported')
        profile = await request.app.state.profile_provider.exchange(body.code, body.verifier)
        return await request.app.state.gateway.issue(profile)

    @routes.post('/refresh')
    async def refresh(body: Refresh, request: Request):
        if request.url.query:
            raise HTTPException(400, 'query_parameters_not_supported')
        return await request.app.state.gateway.refresh(body.refresh_token)

    @routes.get('/user')
    async def user(request: Request):
        return await request.app.state.gateway.authenticate(await authenticated_token(request))

    @routes.post('/logout', status_code=204)
    async def logout(request: Request):
        await request.app.state.gateway.request(await authenticated_token(request), 'logout')
        return Response(status_code=204)

    return routes
