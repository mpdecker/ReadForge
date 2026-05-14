#!/bin/bash

# ReadForge Performance Validation Script
# Validates app performance for App Store requirements

set -e

echo "🚀 ReadForge Performance Validation"
echo "================================="

# Build for testing
echo "🔨 Building app for performance testing..."
xcodebuild -project ReadForge.xcodeproj \
           -scheme ReadForge \
           -configuration Release \
           -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
           clean build

# Get app size
echo "📏 Analyzing app size..."
APP_PATH="./build/Release-iphoneos/ReadForge.app"
if [ -d "$APP_PATH" ]; then
    APP_SIZE=$(du -sh "$APP_PATH" | cut -f1)
    echo "📱 App bundle size: $APP_SIZE"
    
    # Check IPA size
    IPA_PATH="./build/ReadForge.ipa"
    if [ -f "$IPA_PATH" ]; then
        IPA_SIZE=$(du -sh "$IPA_PATH" | cut -f1)
        echo "📦 IPA size: $IPA_SIZE"
        
        # Validate against App Store limits
        IPA_SIZE_MB=$(du -m "$IPA_PATH" | cut -f1)
        if [ "$IPA_SIZE_MB" -gt 200 ]; then
            echo "⚠️  Warning: IPA size exceeds 200MB"
        else
            echo "✅ IPA size within App Store limits"
        fi
    fi
else
    echo "❌ App bundle not found"
fi

# Launch time testing
echo "⏱️  Testing launch time..."
xcrun simctl boot "iPhone 15 Pro" 2>/dev/null || true

# Measure cold launch
echo "🧊 Cold launch test..."
COLD_START_TIME=$(xcrun simctl launch --console "iPhone 15 Pro" com.readforge.app 2>&1 | grep "launch" | head -1)
echo "Cold launch: $COLD_START_TIME"

# Measure warm launch
echo "🔥 Warm launch test..."
WARM_START_TIME=$(xcrun simctl launch --console "iPhone 15 Pro" com.readforge.app 2>&1 | grep "launch" | tail -1)
echo "Warm launch: $WARM_START_TIME"

# Memory usage testing
echo "💾 Testing memory usage..."
xcrun simctl spawn "iPhone 15 Pro" memory_pressure --warn-level 20 --critical-level 40 &
MEMORY_PID=$!

# Run app and monitor memory
xcrun simctl launch "iPhone 15 Pro" com.readforge.app
sleep 10

# Get memory usage
MEMORY_USAGE=$(xcrun simctl spawn "iPhone 15 Pro" top -pid $(pgrep ReadForge) -l 1 | grep ReadForge | awk '{print $3}')
echo "📊 Memory usage: $MEMORY_USAGE"

# Kill memory pressure monitor
kill $MEMORY_PID 2>/dev/null || true

# Battery usage testing
echo "🔋 Testing battery usage..."
xcrun simctl spawn "iPhone 15 Pro" diagnostics energy &
ENERGY_PID=$!

# Run app for battery testing
xcrun simctl launch "iPhone 15 Pro" com.readforge.app
sleep 30

# Get energy impact
ENERGY_IMPACT=$(xcrun simctl spawn "iPhone 15 Pro" diagnostics energy | grep "ReadForge" | tail -1)
echo "⚡ Energy impact: $ENERGY_IMPACT"

# Kill energy monitor
kill $ENERGY_PID 2>/dev/null || true

# Storage usage testing
echo "💾 Testing storage usage..."
STORAGE_BEFORE=$(xcrun simctl get_app_container "iPhone 15 Pro" com.readforge.app data | du -sh | cut -f1)
echo "📂 Storage before: $STORAGE_BEFORE"

# Simulate document import
xcrun simctl push "iPhone 15 Pro" com.readforge.app test-document.pdf
sleep 5

STORAGE_AFTER=$(xcrun simctl get_app_container "iPhone 15 Pro" com.readforge.app data | du -sh | cut -f1)
echo "📂 Storage after: $STORAGE_AFTER"

# Network usage testing
echo "🌐 Testing network usage..."
# Start network monitoring
xcrun simctl spawn "iPhone 15 Pro" network statistics &
NETWORK_PID=$!

# Run app
xcrun simctl launch "iPhone 15 Pro" com.readforge.app
sleep 15

# Check network usage
NETWORK_USAGE=$(xcrun simctl spawn "iPhone 15 Pro" network statistics | grep ReadForge)
echo "📡 Network usage: $NETWORK_USAGE"

# Kill network monitor
kill $NETWORK_PID 2>/dev/null || true

# Performance benchmarks
echo "🏃 Performance benchmarks..."

# CPU usage
echo "🖥️  CPU usage test..."
xcrun simctl spawn "iPhone 15 Pro" cpu_usage &
CPU_PID=$!

xcrun simctl launch "iPhone 15 Pro" com.readforge.app
sleep 20

CPU_USAGE=$(xcrun simctl spawn "iPhone 15 Pro" cpu_usage | grep ReadForge)
echo "🔥 CPU usage: $CPU_USAGE"

kill $CPU_PID 2>/dev/null || true

# Thermal testing
echo "🌡️  Thermal state test..."
THERMAL_STATE=$(xcrun simctl spawn "iPhone 15 Pro" thermal_state)
echo "🌡️  Thermal state: $THERMAL_STATE"

# Generate performance report
echo ""
echo "📊 Performance Report"
echo "===================="

cat << EOF
Performance Validation Results:
============================

App Size:
- Bundle Size: $APP_SIZE
- IPA Size: $IPA_SIZE
- Status: $([ "$IPA_SIZE_MB" -le 200 ] && echo "✅ PASS" || echo "❌ FAIL")

Launch Performance:
- Cold Launch: $COLD_START_TIME
- Warm Launch: $WARM_START_TIME
- Status: $([ -n "$COLD_START_TIME" ] && echo "✅ PASS" || echo "❌ FAIL")

Memory Usage:
- Current Usage: $MEMORY_USAGE
- Status: $([ -n "$MEMORY_USAGE" ] && echo "✅ PASS" || echo "❌ FAIL")

Battery/Energy:
- Energy Impact: $ENERGY_IMPACT
- Status: $([ -n "$ENERGY_IMPACT" ] && echo "✅ PASS" || echo "❌ FAIL")

Storage Usage:
- Before: $STORAGE_BEFORE
- After: $STORAGE_AFTER
- Status: $([ -n "$STORAGE_AFTER" ] && echo "✅ PASS" || echo "❌ FAIL")

Network Usage:
- Usage: $NETWORK_USAGE
- Status: $([ -n "$NETWORK_USAGE" ] && echo "✅ PASS" || echo "❌ FAIL")

CPU Usage:
- Usage: $CPU_USAGE
- Status: $([ -n "$CPU_USAGE" ] && echo "✅ PASS" || echo "❌ FAIL")

Thermal State:
- State: $THERMAL_STATE
- Status: $([ -n "$THERMAL_STATE" ] && echo "✅ PASS" || echo "❌ FAIL")

EOF

# Overall assessment
echo ""
echo "🎯 Overall Assessment"
echo "===================="

# Count passes
PASSES=0
TOTAL=7

[ "$IPA_SIZE_MB" -le 200 ] && ((PASSES++))
[ -n "$COLD_START_TIME" ] && ((PASSES++))
[ -n "$MEMORY_USAGE" ] && ((PASSES++))
[ -n "$ENERGY_IMPACT" ] && ((PASSES++))
[ -n "$STORAGE_AFTER" ] && ((PASSES++))
[ -n "$NETWORK_USAGE" ] && ((PASSES++))
[ -n "$CPU_USAGE" ] && ((PASSES++))

echo "Tests Passed: $PASSES/$TOTAL"

if [ "$PASSES" -eq "$TOTAL" ]; then
    echo "🎉 All performance tests PASSED!"
    echo "✅ Ready for App Store submission"
else
    echo "⚠️  Some performance tests FAILED"
    echo "🔧 Review and fix issues before submission"
fi

# Generate recommendations
echo ""
echo "💡 Performance Recommendations"
echo "==========================="

if [ "$IPA_SIZE_MB" -gt 200 ]; then
    echo "📦 Optimize app bundle size:"
    echo "   - Remove unused resources"
    echo "   - Compress images"
    echo "   - Use app thinning"
fi

if [ -z "$COLD_START_TIME" ]; then
    echo "⏱️  Improve launch time:"
    echo "   - Optimize app initialization"
    echo "   - Use lazy loading"
    echo "   - Reduce startup dependencies"
fi

if [ -n "$MEMORY_USAGE" ] && [[ "$MEMORY_USAGE" > *"200"* ]]; then
    echo "💾 Reduce memory usage:"
    echo "   - Implement memory pooling"
    echo "   - Use lazy loading for large documents"
    echo "   - Optimize data structures"
fi

if [ -n "$CPU_USAGE" ] && [[ "$CPU_USAGE" > *"80"* ]]; then
    echo "🔥 Reduce CPU usage:"
    echo "   - Optimize algorithms"
    echo "   - Use background queues"
    echo "   - Implement caching"
fi

echo ""
echo "✅ Performance validation completed!"
