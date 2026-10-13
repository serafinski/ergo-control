#!/bin/zsh
set -eu
cd "${0:A:h:h}"
swift build -c release
app="$PWD/build/Ergo Probe.app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/ErgoProbe "$app/Contents/MacOS/ErgoProbe"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.local.ergocontrol.probe</string>
<key>CFBundleName</key><string>Ergo Probe</string>
<key>CFBundleExecutable</key><string>ErgoProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSBluetoothAlwaysUsageDescription</key><string>Observe only your PT Ergo keyboard's configuration notifications to identify its extra controls. No configuration commands are sent.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
print "Built: $app"
