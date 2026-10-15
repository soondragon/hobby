#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
TRAINER_BINARY="$(swift build --show-bin-path)/PokeTokenBar"
# Outside iCloud to avoid extended attributes invalidating local ad-hoc signatures.
TRAINER_APP="$HOME/Applications/Hobby Trainer Cloud Preview.app"
mkdir -p "$TRAINER_APP/Contents/MacOS" "$TRAINER_APP/Contents/Resources"
cp "$TRAINER_BINARY" "$TRAINER_APP/Contents/MacOS/PokeTokenBar"
cp config/TrainerCloud.json "$TRAINER_APP/Contents/Resources/TrainerCloud.json"
python3 - "$TRAINER_APP/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as output:
    plistlib.dump({
        'CFBundleIdentifier': 'io.github.soondragon.hobby.cloud.preview',
        'CFBundleName': 'Hobby Trainer Cloud Preview',
        'CFBundleExecutable': 'PokeTokenBar',
        'CFBundlePackageType': 'APPL',
        'CFBundleShortVersionString': '0.2.0',
        'NSHighResolutionCapable': True,
        'CloudPreviewOnly': True,
        'CFBundleURLTypes': [{'CFBundleURLName': 'Trainer cloud authentication',
                              'CFBundleURLSchemes': ['hobbytrainer']}],
    }, output)
PY
codesign --force -s - "$TRAINER_APP"
echo "$TRAINER_APP"
