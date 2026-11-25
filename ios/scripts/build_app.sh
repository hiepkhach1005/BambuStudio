#!/usr/bin/env bash
# Build, sign, install and launch the iPad app. Usage: build_app.sh <device-udid> [--no-install]
set -euo pipefail
IOS="$(cd "$(dirname "$0")/.." && pwd)"; REPO="$IOS/.."
export PATH="$IOS/build/venv/bin:$PATH" IOS_DEPS_PREFIX="$IOS/build/prefix"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"; OUT="$IOS/build/swift"; mkdir -p "$OUT"
BID=dev.touchstudio.slicespike   # same id as the spike: free accounts may only register a few per week
python3 "$IOS/tools/gen_layout.py" "$REPO/src/slic3r/GUI/Tab.cpp" "$IOS/build/layout.json" 2>/dev/null
xcrun swiftc -sdk "$SDK" -target arm64-apple-ios18.0 -swift-version 5 -O -wmo -parse-as-library -module-name TouchStudio \
  -import-objc-header "$IOS/app/engine/Bridge.h" -c "$IOS"/app/swift/*.swift -o "$OUT/app.o"
"$IOS/scripts/build_core.sh" touchstudio
[ "${2:-}" = --no-install ] && exit 0
DEV="$1"; SIGN="$IOS/build/signing/Release-iphoneos/SliceSpike.app"; APP="$IOS/build/pkg/TouchStudio.app"
mkdir -p "$APP/bbl_res/profiles" "$APP/bbl_res/i18n"
cp "$SIGN/Info.plist" "$SIGN/embedded.mobileprovision" "$APP/"
cp "$IOS/build/core/touchstudio.app/touchstudio" "$APP/SliceSpike"
cp "$IOS/build/layout.json" "$APP/"
P="$APP/Info.plist"
for kv in CFBundleDisplayName=TouchStudio CFBundleName=TouchStudio CFBundleShortVersionString=0.1 CFBundleVersion=2 \
  "NSLocalNetworkUsageDescription=Connect to 3D printers on your local network."; do plutil -replace "${kv%%=*}" -string "${kv#*=}" "$P"; done
plutil -replace UILaunchScreen -json '{}' "$P"
plutil -replace UIFileSharingEnabled -bool YES "$P"; plutil -replace LSSupportsOpeningDocumentsInPlace -bool YES "$P"
plutil -replace UIRequiresFullScreen -bool NO "$P"
plutil -replace UISupportedInterfaceOrientations -json '["UIInterfaceOrientationLandscapeLeft","UIInterfaceOrientationLandscapeRight","UIInterfaceOrientationPortrait","UIInterfaceOrientationPortraitUpsideDown"]' "$P"
plutil -replace CFBundleDocumentTypes -json '[{"CFBundleTypeName":"3D model","LSHandlerRank":"Alternate","CFBundleTypeRole":"Editor","LSItemContentTypes":["dev.touchstudio.3mf","public.standard-tesselated-geometry-format","public.geometry-definition-format"]}]' "$P"
plutil -replace UTImportedTypeDeclarations -json '[{"UTTypeIdentifier":"dev.touchstudio.3mf","UTTypeConformsTo":["public.data"],"UTTypeDescription":"3MF","UTTypeTagSpecification":{"public.filename-extension":["3mf"]}}]' "$P"
rsync -a "$REPO/resources/profiles/BBL" "$REPO/resources/profiles/BBL.json" "$APP/bbl_res/profiles/"
for d in info flush printers filament_mixing data cert fonts; do [ -e "$REPO/resources/$d" ] && rsync -a "$REPO/resources/$d" "$APP/bbl_res/"; done
rsync -a "$REPO/resources/i18n/" "$APP/bbl_res/i18n/"
codesign -d --entitlements "$IOS/build/ent.plist" --xml "$SIGN" 2>/dev/null
ID=$(security find-identity -v -p codesigning | awk '/Apple Development/{print $2; exit}')
codesign -f -s "$ID" --entitlements "$IOS/build/ent.plist" "$APP"
xcrun devicectl device install app --device "$DEV" "$APP" | tail -3
xcrun devicectl device process launch --device "$DEV" --terminate-existing "$BID" ${2:+"$2"}
