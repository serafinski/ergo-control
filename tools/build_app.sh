#!/bin/zsh
set -eu
cd "${0:A:h:h}"
if [[ -n "${ERGO_CODESIGN_IDENTITY:-}" ]]; then
  identity="$ERGO_CODESIGN_IDENTITY"
  signing_options=()
else
  identity="$(python3 tools/setup_local_signing.py)"
  signing_options=(--keychain "$PWD/build/local-signing/ErgoDevelopment.keychain-db")
fi
app="$PWD/build/Ergo Control.app"
for asset in AppIcon.icns AppIcon.png ErgoMarkTemplate.png ErgoMarkTemplate@2x.png; do
  [[ -f "resources/$asset" ]] || { print -u2 "Missing resources/$asset. Run: swift tools/render_icons.swift resources"; exit 1; }
done
if [[ "${ERGO_REUSE_HELPER:-0}" == 1 ]]; then
  # GUI-only updates preserve the installed helper's signature and TCC identity.
  for file in Contents/Library/HelperTools/ErgoInputHelper Contents/Library/LaunchDaemons/dev.local.ergocontrol.inputhelper.plist Contents/Resources/ErgoInputHelper-Install.pkg Contents/Resources/ErgoInputHelper-Uninstall.pkg; do
    [[ -f "$app/$file" ]] || { print -u2 "Cannot reuse helper: missing $file"; exit 1; }
  done
  codesign --verify --strict "$app/Contents/Library/HelperTools/ErgoInputHelper"
fi
swift build -c release --product ErgoControl
swift build -c release --product ErgoCodexHook
mkdir -p "$app/Contents/MacOS" "$app/Contents/Library/HelperTools" "$app/Contents/Library/LaunchDaemons" "$app/Contents/Resources"
cp resources/AppIcon.icns resources/AppIcon.png resources/ErgoMarkTemplate.png resources/ErgoMarkTemplate@2x.png "$app/Contents/Resources/"
cp .build/release/ErgoControl "$app/Contents/MacOS/ErgoControl"
cp .build/release/ErgoCodexHook "$app/Contents/Resources/ErgoCodexHook"
codesign --force --sign "$identity" "${signing_options[@]}" --identifier dev.local.ergocontrol.codexhook "$app/Contents/Resources/ErgoCodexHook"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.local.ergocontrol.app</string>
<key>CFBundleName</key><string>Ergo Control</string>
<key>CFBundleExecutable</key><string>ErgoControl</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundleShortVersionString</key><string>0.6.5</string>
<key>CFBundleVersion</key><string>44</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSBluetoothAlwaysUsageDescription</key><string>Connect only to your paired PT Ergo to enable its extra controls, read battery status, adjust keyboard lighting and the dial indicator, and restore its saved mode when mappings stop.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Pin the app's identifier and certificate in the helper's secured Info.plist.
codesign --force --sign "$identity" "${signing_options[@]}" "$app"
python3 tools/helper_signing.py prepare "$app" "$PWD/build/input-helper-info.plist"
if [[ "${ERGO_REUSE_HELPER:-0}" != 1 ]]; then
swift build -c release --product ErgoInputHelper \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$PWD/build/input-helper-info.plist"
cp .build/release/ErgoInputHelper "$app/Contents/Library/HelperTools/ErgoInputHelper"
codesign --force --sign "$identity" "${signing_options[@]}" --identifier dev.local.ergocontrol.inputhelper "$app/Contents/Library/HelperTools/ErgoInputHelper"
cp resources/dev.local.ergocontrol.inputhelper.plist "$app/Contents/Library/LaunchDaemons/"
python3 tools/build_helper_packages.py "$app"
fi
codesign --force --sign "$identity" "${signing_options[@]}" "$app"
python3 tools/helper_signing.py verify "$app" "$PWD/build/input-helper-info.plist"
codesign --verify --strict "$app"
codesign --verify --strict "$app/Contents/Library/HelperTools/ErgoInputHelper"
"$app/Contents/Library/HelperTools/ErgoInputHelper" --self-check
print "Built: $app"
print "The helper is bundled only; this script does not register or start it."
