#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
TRAINER_APP="$HOME/Applications/Floating Encounter Preview.app"
mkdir -p "$TRAINER_APP/Contents/MacOS"
cp "$(swift build --show-bin-path)/PokeTokenBar" "$TRAINER_APP/Contents/MacOS/PokeTokenBar"
python3 - "$TRAINER_APP/Contents/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1],'wb') as file:
 plistlib.dump({'CFBundleIdentifier':'io.github.soondragon.hobby.encounter.preview','CFBundleName':'Floating Encounter Preview','CFBundleExecutable':'PokeTokenBar','CFBundlePackageType':'APPL','EncounterPreviewOnly':True,'NSHighResolutionCapable':True},file)
PY
codesign --force -s - "$TRAINER_APP"
