"""Bound unauthenticated credential bodies before JSON parsing."""
import asyncio
from starlette.responses import JSONResponse


class AuthenticationBodyLimit:
    def __init__(self, app): self.app = app

    async def __call__(self, scope, receive, send):
        if scope['type'] != 'http' or scope['method'] != 'POST' or not scope['path'].startswith(('/api/auth/', '/api/encounter')):
            return await self.app(scope, receive, send)
        body = bytearray()
        try:
            async with asyncio.timeout(10):
                while True:
                    message = await receive()
                    if message['type'] == 'http.disconnect': return
                    body.extend(message.get('body', b''))
                    if len(body) > 8192:
                        return await JSONResponse({'detail': 'request_too_large'}, status_code=413)(scope, receive, send)
                    if not message.get('more_body', False): break
        except TimeoutError:
            return await JSONResponse({'detail': 'request_timeout'}, status_code=408)(scope, receive, send)
        delivered = False
        async def bounded_receive():
            nonlocal delivered
            if not delivered:
                delivered = True
                return {'type': 'http.request', 'body': bytes(body), 'more_body': False}
            return await receive()
        await self.app(scope, bounded_receive, send)
