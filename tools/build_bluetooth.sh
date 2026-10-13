#!/bin/zsh
set -eu
cd "${0:A:h:h}"
swift build -c release --product ErgoBluetooth
app="$PWD/build/Ergo Bluetooth.app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/ErgoBluetooth "$app/Contents/MacOS/ErgoBluetooth"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.local.ergocontrol.bluetooth</string>
<key>CFBundleName</key><string>Ergo Bluetooth</string>
<key>CFBundleExecutable</key><string>ErgoBluetooth</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.2</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSBluetoothAlwaysUsageDescription</key><string>Read your PT Ergo keyboard's configuration mode and test its extra controls with a temporary, automatically restored mode change.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
print "Built: $app"
