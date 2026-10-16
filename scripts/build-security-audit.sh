#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
TRAINER_BINARY="$(swift build --show-bin-path)/PokeTokenBar"
TRAINER_APP="$HOME/Applications/Trainer Security Audit.app"
mkdir -p "$TRAINER_APP/Contents/MacOS" "$TRAINER_APP/Contents/Resources"
cp "$TRAINER_BINARY" "$TRAINER_APP/Contents/MacOS/PokeTokenBar"
cp config/TrainerCloud.json "$TRAINER_APP/Contents/Resources/TrainerCloud.json"
python3 - "$TRAINER_APP/Contents/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1],'wb') as output:
    plistlib.dump(dict(CFBundleIdentifier='io.github.soondragon.hobby.security',
        CFBundleName='Trainer Security Audit',CFBundleExecutable='PokeTokenBar',
        CFBundlePackageType='APPL',SecurityAuditOnly=True,
        LSEnvironment={"TRAINER_PROFILE_MANUAL_BROWSER":"1"},
        CFBundleURLTypes=[dict(CFBundleURLSchemes=['hobbytrainer'])]),output)
PY
codesign --force -s - "$TRAINER_APP"
echo "$TRAINER_APP"
