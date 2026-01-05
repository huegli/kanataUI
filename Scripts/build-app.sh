#!/bin/bash
set -e

# Build configuration
APP_NAME="KanataUI"
BUNDLE_ID="com.nikolai.KanataUI"
VERSION="1.0.12"
BUILD_DIR="Build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "Building $APP_NAME..."

# Clean and build release
swift build -c release

# Create app bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp .build/release/KanataUI "$APP_BUNDLE/Contents/MacOS/"

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2024. All rights reserved.</string>
</dict>
</plist>
PLIST

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Ad-hoc code signing
# This creates a valid signature without requiring an Apple Developer certificate.
# The app will still be blocked by Gatekeeper on other Macs, but combined with
# removing the quarantine attribute, it allows the app to run on Macs you own.
echo "Signing $APP_NAME (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE"

# Remove quarantine attribute from the built app
# This prevents the "app is damaged" error when copying to another Mac.
# Note: The quarantine attribute may be re-added during transfer (e.g., AirDrop),
# so you may need to run xattr -cr on the target Mac as well.
xattr -cr "$APP_BUNDLE"

echo ""
echo "✓ Built $APP_BUNDLE"
echo ""
echo "To install locally:"
echo "  cp -r \"$APP_BUNDLE\" /Applications/"
echo ""
echo "To install on another Mac you own:"
echo "  1. Copy $APP_BUNDLE to the other Mac"
echo "  2. Run: xattr -cr /path/to/KanataUI.app"
echo "  3. Move to /Applications/ if desired"
echo ""
echo "Or open the Build folder:"
echo "  open $BUILD_DIR"
