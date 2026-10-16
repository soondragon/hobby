"""Public signed metadata and streamed packages; no account state or credentials."""
import base64
import json
import re
from pathlib import Path
from fastapi import APIRouter, HTTPException
from fastapi.responses import HTMLResponse, JSONResponse, StreamingResponse


def router(directory: Path | None = None):
    result = APIRouter()
    root = directory or Path(__file__).resolve().parents[1] / 'releases'

    def current():
        try:
            envelope = json.loads((root / 'latest.json').read_text())
            payload = json.loads(base64.b64decode(envelope['payload'], validate=True))
            filename = payload['downloadURL'].rsplit('/', 1)[1]
            if not re.fullmatch(r'trainer-[0-9]+\.[0-9]+\.[0-9]+-[a-f0-9]{64}\.zip', filename):
                raise ValueError()
            file = root / filename
            if file.stat().st_size != payload['size']:
                raise ValueError()
            return envelope, filename, file
        except (OSError, ValueError, KeyError, TypeError):
            raise HTTPException(503, 'release_unavailable') from None

    @result.get('/api/app-release')
    async def release():
        envelope, _, _ = current()
        return JSONResponse(envelope)

    @result.get('/app', response_class=HTMLResponse)
    async def landing():
        _, filename, _ = current()
        version = filename.split('-')[1]
        return HTMLResponse(f"""<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Hobby Trainer Cloud</title><style>body{{font:18px system-ui;background:#f6f7fb;color:#263144;margin:0;padding:10vh 8vw}}main{{max-width:680px;margin:auto;background:white;border-radius:28px;padding:48px;box-shadow:0 16px 50px #26314412}}h1{{font-size:36px}}a{{display:inline-block;background:#354ed5;color:white;text-decoration:none;padding:16px 22px;border-radius:14px}}small{{display:block;color:#667085;margin-top:28px;line-height:1.7}}</style><main><p>macOS · Apple Silicon · v{version}</p><h1>Hobby Trainer Cloud</h1><p>GitHub alias로 연결하고, 포켓몬은 서버에 저장하세요.</p><p>원본 앱과 분리된 업데이트 채널을 사용합니다.</p><a href="/downloads/cloud/{filename}">Mac 앱 다운로드</a><small>macOS 14 이상 · 이메일·저장소 권한 요청 없음<br>현재 Apple 공증 전 테스트 배포입니다.</small></main></html>""")

    @result.get('/downloads/cloud/{filename}')
    def download(filename: str):
        _, expected, file = current()
        if filename != expected:
            # Retained immutable packages must survive a feed promotion during a download.
            if not re.fullmatch(r'trainer-[0-9]+\.[0-9]+\.[0-9]+-[a-f0-9]{64}\.zip', filename):
                raise HTTPException(404, 'release_not_found')
            file = root / filename
            if not file.is_file() or not 0 < file.stat().st_size <= 64_000_000:
                raise HTTPException(404, 'release_not_found')

        def chunks():
            with file.open('rb') as stream:
                while chunk := stream.read(131072):
                    yield chunk
        return StreamingResponse(chunks(), media_type='application/zip', headers={
            'Content-Disposition': f'attachment; filename="{expected}"',
            'Cache-Control': 'public, max-age=31536000, immutable',
        })

    return result
