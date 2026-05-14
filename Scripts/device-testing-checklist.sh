#!/bin/bash

# ReadForge Device Testing Checklist
# Automated testing script for physical devices

set -e

echo "🧪 ReadForge Device Testing Checklist"
echo "====================================="

# Check if device is connected
echo "📱 Checking for connected devices..."
if ! xcrun simctl list devices | grep -q "iPhone"; then
    echo "⚠️  No physical devices found. Please connect a device for testing."
    echo "Available simulators:"
    xcrun simctl list devices | grep "iPhone"
    exit 1
fi

# Get connected device info
DEVICE_ID=$(xcrun simctl list devices | grep "iPhone" | head -1 | grep -o "[A-F0-9-]*")
echo "✅ Found device: $DEVICE_ID"

# Build for device
echo "🔨 Building for physical device..."
xcodebuild -project ReadForge.xcodeproj \
           -scheme ReadForge \
           -configuration Debug \
           -destination "id=$DEVICE_ID" \
           clean build

# Install on device
echo "📲 Installing on device..."
xcrun devicectl install app --device $DEVICE_ID ./build/Debug-iphoneos/ReadForge.app

# Run automated tests
echo "🧪 Running automated tests..."
xcodebuild test \
           -project ReadForge.xcodeproj \
           -scheme ReadForge \
           -destination "id=$DEVICE_ID" \
           -only-testing:ReadForgeUITests

echo ""
echo "📋 Manual Testing Checklist"
echo "=========================="

# Manual testing items
cat << 'EOF'
Core Functionality Tests:
□ App launches successfully
□ Library view loads correctly
□ Document import works (PDF, EPUB, TXT)
□ Text extraction functions properly
□ Audio playback starts/stops correctly
□ Progress tracking saves properly
□ Background audio works with lock screen
□ Settings screen opens and functions
□ Voice selection works
□ Playback speed adjustment works

Performance Tests:
□ App launches in < 3 seconds
□ Memory usage stays < 200MB
□ No crashes during normal usage
□ Large documents (>100 pages) load properly
□ Battery usage is reasonable
□ Thermal management works under stress

Accessibility Tests:
□ VoiceOver navigation works
□ Dynamic Type scaling works
□ High contrast mode works
□ Reduce motion works
□ Switch control works
□ Guided Access works

Security Tests:
□ File permissions work correctly
□ Data encryption functions
□ No data leaks to cloud
□ Privacy manifest respected
□ Keychain storage works

Device-Specific Tests:
□ iPhone notch handling works
□ iPad multitasking works
□ Split view works on iPad
□ Landscape orientation works
□ Dark mode works
□ System font changes respected

Edge Cases:
□ Low storage scenarios
□ Low battery scenarios
□ Airplane mode works
□ Network interruptions handled
□ App backgrounding/foregrounding
□ Memory pressure scenarios

App Store Compliance:
□ No crashes during testing
□ Proper error messages
□ No private API usage
□ App size under 200MB
□ Proper code signing
□ Privacy policy accessible

EOF

echo ""
echo "📊 Performance Monitoring"
echo "========================"

# Memory usage monitoring
echo "📈 Monitoring memory usage..."
xcrun devicectl device process list --device $DEVICE_ID | grep ReadForge

# Battery usage
echo "🔋 Battery usage check..."
xcrun devicectl device diagnose power --device $DEVICE_ID

# Storage usage
echo "💾 Storage usage check..."
xcrun devicectl device list apps --device $DEVICE_ID | grep ReadForge

echo ""
echo "✅ Device testing checklist completed!"
echo "📝 Complete manual testing and mark items as done"
echo "🚀 Ready for App Store submission when all items pass"
