#!/bin/zsh
set -eu
cd "${0:A:h:h}"
swift build -c release --product ErgoControl
app="$PWD/build/Ergo Control.app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/ErgoControl "$app/Contents/MacOS/ErgoControl"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.local.ergocontrol.app</string>
<key>CFBundleName</key><string>Ergo Control</string>
<key>CFBundleExecutable</key><string>ErgoControl</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSBluetoothAlwaysUsageDescription</key><string>Connect only to your paired PT Ergo to enable its extra controls, read battery status, and restore its saved mode when mappings stop.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
print "Built: $app"
