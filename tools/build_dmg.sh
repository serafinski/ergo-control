#!/bin/zsh
set -eu
cd "${0:A:h:h}"
app="${1:-$PWD/build/Ergo Control.app}"
[[ -d "$app" ]] || { print -u2 "Build Ergo Control.app first."; exit 1; }
codesign --verify --deep --strict "$app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
[[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 "Invalid app version"; exit 1; }
mkdir -p dist
staging="$(mktemp -d "$PWD/build/dmg.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/Ergo Control.app"
ln -s /Applications "$staging/Applications"
cp docs/INSTALL.txt "$staging/Read me first.txt"
cp LICENSE "$staging/LICENSE.txt"
architectures="$(lipo -archs "$app/Contents/MacOS/ErgoControl")"
if [[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]]; then
  architecture=universal
elif [[ "$architectures" == arm64 || "$architectures" == x86_64 ]]; then
  architecture="$architectures"
else
  print -u2 "Unexpected app architectures: $architectures"; exit 1
fi
dmg="$PWD/dist/Ergo-Control-$version-$architecture.dmg"
hdiutil create -volname 'Ergo Control' -srcfolder "$staging" -format UDZO -ov "$dmg"
hdiutil verify "$dmg"
(cd dist && shasum -a 256 "${dmg:t}" > "${dmg:t}.sha256")
print "Built: $dmg"
