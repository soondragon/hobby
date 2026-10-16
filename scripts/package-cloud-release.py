#!/usr/bin/env python3
"""Build signed update metadata without uploading private signing material."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile


def package(app: Path, signing_key: Path, output: Path) -> dict:
    root = Path(__file__).resolve().parents[1]
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    version = info.get('CFBundleShortVersionString', '')
    if (app.name != 'PokeTokenBar Cloud.app' or info.get('CFBundleIdentifier') != 'io.github.soondragon.hobby.cloud'
            or info.get('CFBundleExecutable') != 'PokeTokenBar' or not re.fullmatch(r'\d+\.\d+\.\d+', version)):
        raise ValueError('Unexpected cloud application identity/version')
    if not signing_key.is_file() or signing_key.stat().st_mode & 0o077:
        raise ValueError('Existing owner-only release signing key required')
    subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(app)], check=True)
    with tempfile.TemporaryDirectory(prefix='trainer-release-') as workspace:
        temporary = Path(workspace)
        subprocess.run(['swift', str(root/'scripts/cloud-release-sign.swift'), str(signing_key), 'trust', str(temporary/'trust.json')], check=True)
        actual = json.loads((temporary/'trust.json').read_text())
        expected = json.loads((root/'config/TrainerUpdates.json').read_text())
        if actual != expected:
            raise ValueError('Signing key does not match the installed application trust anchor')
        archive = temporary/'package.zip'
        subprocess.run(['/usr/bin/ditto', '--norsrc', '--noextattr', '-c', '-k', '--keepParent', str(app), str(archive)], check=True)
        with archive.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        size = archive.stat().st_size
        if not 0 < size <= 64_000_000:
            raise ValueError('Release package exceeds the native download bound')
        name = f'trainer-{version}-{digest}.zip'
        payload = dict(version=version, bundleID=info['CFBundleIdentifier'],
                       downloadURL=f'https://hobby-trainer.vercel.app/downloads/cloud/{name}',
                       sha256=digest, size=size, minimumOS=14, architecture='arm64')
        (temporary/'payload.json').write_text(json.dumps(payload, sort_keys=True, separators=(',', ':')))
        subprocess.run(['swift', str(root/'scripts/cloud-release-sign.swift'), str(signing_key), str(temporary/'payload.json'), str(temporary/'latest.json')], check=True)
        output.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(archive, output/name)
        shutil.copyfile(temporary/'latest.json', output/'latest.next.json')
        os.replace(output/'latest.next.json', output/'latest.json')
        return payload


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--signing-key', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('server/releases'))
    options = parser.parse_args()
    release = package(options.app.resolve(), options.signing_key.resolve(), options.output.resolve())
    print(f"Cloud release {release['version']}: {release['size']} bytes, SHA-256 {release['sha256']}")
