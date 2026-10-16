#!/bin/bash
# Local cloud build. Does not replace the upstream installation or install a login agent.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
TRAINER_BINARY="$(swift build -c release --show-bin-path)/PokeTokenBar"
TRAINER_APP="${TRAINER_APP_DESTINATION:-$HOME/Applications/PokeTokenBar Cloud.app}"
mkdir -p "$TRAINER_APP/Contents/MacOS" "$TRAINER_APP/Contents/Resources"
cp "$TRAINER_BINARY" "$TRAINER_APP/Contents/MacOS/PokeTokenBar"
cp config/TrainerUpdates.json "$TRAINER_APP/Contents/Resources/TrainerUpdates.json"
cp config/TrainerCloud.json "$TRAINER_APP/Contents/Resources/TrainerCloud.json"
cp assets/AppIcon.icns "$TRAINER_APP/Contents/Resources/AppIcon.icns"
python3 - "$TRAINER_APP/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as output:
    plistlib.dump({
        'CFBundleIdentifier': 'io.github.soondragon.hobby.cloud',
        'CFBundleName': 'PokeTokenBar Cloud',
        'CFBundleExecutable': 'PokeTokenBar',
        'CFBundlePackageType': 'APPL',
        'CFBundleShortVersionString': '0.3.0',
        'CFBundleVersion': '1',
        'CFBundleIconFile': 'AppIcon',
        'LSUIElement': True,
        'NSHighResolutionCapable': True,
        'CFBundleURLTypes': [{'CFBundleURLName': 'Trainer cloud authentication',
                              'CFBundleURLSchemes': ['hobbytrainer']}],
    }, output)
PY
cp Sources/PokeTokenBar/Resources/MoveDefinitions.json "$TRAINER_APP/Contents/Resources/"
cp -R Sources/PokeTokenBar/Resources/BattleSpells "$TRAINER_APP/Contents/Resources/"
codesign --force -s - "$TRAINER_APP"
codesign --verify --strict "$TRAINER_APP"
echo "$TRAINER_APP"
