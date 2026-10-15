#!/bin/bash
# Builds an isolated debug account window; never installs or replaces PokeTokenBar.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
PROFILE_BINARY="$(swift build --show-bin-path)/PokeTokenBar"
PROFILE_ROOT="$PWD/build/profile-preview"
PROFILE_APP="$PROFILE_ROOT/Hobby Trainer Preview.app"
mkdir -p "$PROFILE_APP/Contents/MacOS" "$PROFILE_ROOT/state"
cp "$PROFILE_BINARY" "$PROFILE_APP/Contents/MacOS/PokeTokenBar"
python3 - "$PROFILE_APP/Contents/Info.plist" "$PROFILE_ROOT/state" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as output:
    plistlib.dump({
        'CFBundleIdentifier': 'io.github.soondragon.hobby.preview',
        'CFBundleName': 'Hobby Trainer Preview',
        'CFBundleExecutable': 'PokeTokenBar',
        'CFBundlePackageType': 'APPL',
        'CFBundleShortVersionString': '0.1.0',
        'NSHighResolutionCapable': True,
        'ProfilePreviewOnly': True,
        'ProfilePreviewDirectory': sys.argv[2],
    }, output)
PY
codesign --force -s - "$PROFILE_APP"
echo "$PROFILE_APP"
