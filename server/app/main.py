from contextlib import asynccontextmanager
import json
import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import ValidationError
from .configuration import Configuration
from .gateway import SupabaseGateway
from .models import SaveCommand

MAX_BODY = 1_048_576


@asynccontextmanager
async def lifespan(app: FastAPI):
    configuration = Configuration.from_environment()
    # Redirects are never followed with a user's bearer token.
    async with httpx.AsyncClient(timeout=httpx.Timeout(10, connect=5), follow_redirects=False,
                                 limits=httpx.Limits(max_connections=20, max_keepalive_connections=10)) as client:
        app.state.gateway = SupabaseGateway(configuration, client)
        yield


def create_app(gateway=None) -> FastAPI:
    app = FastAPI(title="Trainer Cloud", docs_url=None, redoc_url=None, openapi_url=None,
                  lifespan=None if gateway is not None else lifespan)
    if gateway is not None:
        app.state.gateway = gateway

    @app.middleware("http")
    async def security_headers(request: Request, call_next):
        response = await call_next(request)
        response.headers["Cache-Control"] = "private, no-store, max-age=0"
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Referrer-Policy"] = "no-referrer"
        return response

    async def authenticated_token(request: Request) -> str:
        header = request.headers.get("authorization", "")
        parts = header.split(" ")
        if len(parts) != 2 or parts[0].lower() != "bearer" or not 1 <= len(parts[1]) <= 8192 or any(c.isspace() for c in parts[1]):
            raise HTTPException(401, "authentication_required")
        if request.url.query:
            raise HTTPException(400, "query_parameters_not_supported")
        await app.state.gateway.authenticate(parts[1])
        return parts[1]

    @app.get("/api/health")
    async def health():
        return {"status": "ok", "schemaVersion": 1}

    @app.get("/api/companion")
    async def get_companion(request: Request):
        token = await authenticated_token(request)
        return await app.state.gateway.read(token)

    @app.put("/api/companion")
    async def put_companion(request: Request):
        token = await authenticated_token(request)
        if request.headers.get("content-type", "").split(";")[0].strip().lower() != "application/json":
            raise HTTPException(415, "json_required")
        raw = bytearray()
        async for chunk in request.stream():
            raw.extend(chunk)
            if len(raw) > MAX_BODY:
                raise HTTPException(413, "save_too_large")
        try:
            # Reject NaN/Infinity rather than passing non-JSON values to PostgreSQL.
            body = json.loads(raw, parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
            command = SaveCommand.model_validate_json(json.dumps(body, allow_nan=False))
        except (ValueError, ValidationError, RecursionError, TypeError):
            # Pydantic's detailed input errors may contain private save contents; do not echo them.
            raise HTTPException(422, "invalid_save") from None
        return await app.state.gateway.write(token, command)

    @app.exception_handler(Exception)
    async def unexpected_error(request: Request, exc: Exception):
        # No token, upstream response, traceback or player payload is sent to the caller.
        return JSONResponse(status_code=500, content={"detail": "request_failed"})

    return app


app = create_app()
