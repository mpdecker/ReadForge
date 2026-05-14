#!/bin/bash

# ReadForge App Store Preparation Script
# This script prepares the app for App Store submission

set -e

echo "🚀 Preparing ReadForge for App Store submission..."

# Check Xcode version
XCODE_VERSION=$(xcodebuild -version | head -n 1 | cut -d' ' -f3)
echo "✅ Using Xcode $XCODE_VERSION"

# Verify code signing certificates
echo "🔐 Checking code signing certificates..."
if ! security find-identity -v -p codesigning | grep -q "iPhone Distribution"; then
    echo "❌ No iPhone Distribution certificate found"
    echo "Please create a distribution certificate in Apple Developer Portal"
    exit 1
fi
echo "✅ Distribution certificate found"

# Check provisioning profile
echo "📋 Checking provisioning profile..."
PROFILE_PATH="$HOME/Library/MobileDevice/Provisioning Profiles"
if [ ! -d "$PROFILE_PATH" ]; then
    echo "❌ No provisioning profiles directory found"
    exit 1
fi

PROFILE_COUNT=$(ls -1 "$PROFILE_PATH" | wc -l)
if [ "$PROFILE_COUNT" -eq 0 ]; then
    echo "❌ No provisioning profiles found"
    echo "Please download provisioning profile from Apple Developer Portal"
    exit 1
fi
echo "✅ Found $PROFILE_COUNT provisioning profile(s)"

# Clean build directory
echo "🧹 Cleaning build directory..."
rm -rf ~/Library/Developer/Xcode/DerivedData/*/Build/Products/Release-iphoneos

# Archive the app
echo "📦 Creating archive..."
xcodebuild -project ReadForge.xcodeproj \
           -scheme ReadForge \
           -configuration Release \
           -destination generic/platform=iOS \
           -archivePath ./build/ReadForge.xcarchive \
           clean archive \
           CODE_SIGN_STYLE=Manual \
           PROVISIONING_PROFILE_SPECIFIER="" \
           CODE_SIGN_IDENTITY=""

# Export for App Store
echo "📤 Exporting for App Store..."
xcodebuild -exportArchive \
           -archivePath ./build/ReadForge.xcarchive \
           -exportOptionsPlist ExportOptions.plist \
           -exportPath ./build/AppStore

# Validate the IPA
echo "🔍 Validating IPA..."
IPA_PATH="./build/AppStore/ReadForge.ipa"
if [ ! -f "$IPA_PATH" ]; then
    echo "❌ IPA file not found at $IPA_PATH"
    exit 1
fi

# Check app size
IPA_SIZE=$(du -h "$IPA_PATH" | cut -f1)
echo "📏 IPA size: $IPA_SIZE"

# Validate with Application Loader (if available)
if command -v altool &> /dev/null; then
    echo "🔍 Validating with Application Loader..."
    altool --validate-app \
           --file "$IPA_PATH" \
           --type ios \
           --username "$APPLE_ID" \
           --password "$APPLE_PASSWORD" \
           --asc-provider "$TEAM_ID"
else
    echo "⚠️  altool not found, skipping validation"
fi

# Generate checksums
echo "🔐 Generating checksums..."
cd ./build/AppStore
shasum -a 256 ReadForge.ipa > ReadForge.ipa.sha256
cd ../..

echo "✅ App Store preparation complete!"
echo "📁 Build artifacts available in ./build/AppStore/"
echo "🚀 Ready for upload to App Store Connect!"

# Display next steps
echo ""
echo "📋 Next Steps:"
echo "1. Upload to App Store Connect using Xcode Organizer or Transporter"
echo "2. Complete App Store metadata in App Store Connect"
echo "3. Submit for review"
echo "4. Wait for approval (typically 24-48 hours)"
