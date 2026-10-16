#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
TRAINER_APP="$HOME/Applications/Floating Encounter Preview.app"
mkdir -p "$TRAINER_APP/Contents/MacOS" "$TRAINER_APP/Contents/Resources"
cp server/data/move-catalog.json "$TRAINER_APP/Contents/Resources/MoveCatalog.json"
cp "$(swift build --show-bin-path)/PokeTokenBar" "$TRAINER_APP/Contents/MacOS/PokeTokenBar"
python3 - "$TRAINER_APP/Contents/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1],'wb') as file:
 plistlib.dump({'CFBundleIdentifier':'io.github.soondragon.hobby.encounter.preview','CFBundleName':'Floating Encounter Preview','CFBundleExecutable':'PokeTokenBar','CFBundlePackageType':'APPL','EncounterPreviewOnly':True,'NSHighResolutionCapable':True},file)
PY
cp Sources/PokeTokenBar/Resources/MoveDefinitions.json "$TRAINER_APP/Contents/Resources/"
cp -R Sources/PokeTokenBar/Resources/BattleSpells "$TRAINER_APP/Contents/Resources/"
codesign --force -s - "$TRAINER_APP"
