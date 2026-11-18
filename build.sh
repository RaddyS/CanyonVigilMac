#!/bin/zsh
set -eu
cd "${0:A:h}"
app="$PWD/dist/Canyon Vigil.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$PWD/.build/module-cache"
clang -O2 -Wall -Wextra -Wno-deprecated-declarations Sources/vigilctl.c -framework IOKit -framework CoreFoundation -o "$app/Contents/MacOS/vigilctl"
swiftc -swift-version 5 -O -parse-as-library -module-cache-path "$PWD/.build/module-cache" -target "$(uname -m)-apple-macosx13.0" Sources/CanyonVigil.swift -o "$app/Contents/MacOS/CanyonVigil" -framework SwiftUI -framework AppKit -framework ApplicationServices
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CanyonVigil</string>
<key>CFBundleIdentifier</key><string>local.canyon.vigil.mac</string>
<key>CFBundleName</key><string>Canyon Vigil</string>
<key>CFBundleDisplayName</key><string>Canyon Vigil</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app/Contents/MacOS/vigilctl"
codesign --force --sign - "$app"
echo "Built $app"
