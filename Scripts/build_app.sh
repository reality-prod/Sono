#!/bin/bash
# Compiles Sono in release mode and wraps it into build/Sono.app with Apple Help Book.
set -e; cd "$(dirname "$0")/.."

# Ensure help index is up to date
if [ -x help/build_help.sh ]; then
    help/build_help.sh
fi

swift build -c release
A=build/Sono.app; rm -rf $A; mkdir -p $A/Contents/MacOS $A/Contents/Resources
cp .build/release/Sono $A/Contents/MacOS/Sono
[ -f Design/Sono.icns ] && cp Design/Sono.icns $A/Contents/Resources/
[ -d help/Sono.help ] && cp -R help/Sono.help $A/Contents/Resources/

cat > $A/Contents/Info.plist <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Sono</string>
    <key>CFBundleDisplayName</key><string>Sono</string>
    <key>CFBundleExecutable</key><string>Sono</string>
    <key>CFBundleIdentifier</key><string>app.sono.mac</string>
    <key>CFBundleIconFile</key><string>Sono</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>CFBundleHelpBookFolder</key><string>Sono.help</string>
    <key>CFBundleHelpBookName</key><string>app.sono.mac.help</string>
    <key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict>
</plist>
P
echo "Built $A with Apple Help Book"
