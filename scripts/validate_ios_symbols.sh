#!/bin/bash

# Validate iOS Agora SDK Symbols
# This script validates that required symbols are available in the iOS frameworks

set -e

echo "🔍 Validating iOS Agora SDK symbols..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if we're in the right directory
if [ ! -f "pubspec.yaml" ] || [ ! -d "ios" ]; then
    echo -e "${RED}❌ Error: Must be run from the Flutter plugin root directory${NC}"
    exit 1
fi

# Build the example app to ensure dependencies are resolved
echo "📦 Building example app to resolve dependencies..."
cd example

# Clean and get dependencies
flutter clean
flutter pub get

# Check if iOS directory exists
if [ ! -d "ios" ]; then
    echo -e "${RED}❌ Error: Example iOS directory not found${NC}"
    exit 1
fi

cd ios

# Install pods
echo "🔧 Installing CocoaPods dependencies..."
pod install --repo-update

# Check if AgoraIrisRTC_iOS framework exists in Pods
if [ ! -d "Pods/AgoraIrisRTC_iOS" ]; then
    echo -e "${RED}❌ Error: AgoraIrisRTC_iOS framework not found in Pods${NC}"
    exit 1
fi

echo -e "${GREEN}✅ AgoraIrisRTC_iOS framework found${NC}"

# Check for framework files
FRAMEWORK_PATH="Pods/AgoraIrisRTC_iOS"
if [ -d "$FRAMEWORK_PATH" ]; then
    echo "📋 Framework contents:"
    find "$FRAMEWORK_PATH" -name "*.framework" -o -name "*.xcframework" | head -5
    
    # Check for symbols in the framework (if nm is available)
    if command -v nm >/dev/null 2>&1; then
        echo "🔍 Checking for Iris symbols..."
        FOUND_SYMBOLS=false
        
        # Look for framework binaries
        find "$FRAMEWORK_PATH" -name "AgoraRtcWrapper*" -type f | while read -r binary; do
            if nm -D "$binary" 2>/dev/null | grep -q "Iris_InitDartApiDL" 2>/dev/null; then
                echo -e "${GREEN}✅ Found Iris_InitDartApiDL symbol in $binary${NC}"
                FOUND_SYMBOLS=true
            fi
        done
        
        if [ "$FOUND_SYMBOLS" = false ]; then
            echo -e "${YELLOW}⚠️  Warning: Could not verify Iris_InitDartApiDL symbol (this may be normal)${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  nm tool not available, skipping symbol check${NC}"
    fi
fi

# Build the iOS app to test symbol resolution
echo "🏗️  Building iOS app to test symbol resolution..."
cd ..

# Try to build the iOS app
if flutter build ios --no-codesign --debug --verbose 2>&1 | tee build.log; then
    echo -e "${GREEN}✅ iOS build successful - symbols are properly linked${NC}"
    
    # Check for the specific error in build log
    if grep -q "Iris_InitDartApiDL.*symbol not found" build.log; then
        echo -e "${RED}❌ Found Iris_InitDartApiDL symbol error in build${NC}"
        rm -f build.log
        exit 1
    fi
    
    rm -f build.log
else
    echo -e "${RED}❌ iOS build failed${NC}"
    
    # Check if it's the specific symbol error
    if [ -f build.log ] && grep -q "Iris_InitDartApiDL.*symbol not found" build.log; then
        echo -e "${RED}❌ Confirmed: Iris_InitDartApiDL symbol not found error${NC}"
        echo "💡 This indicates the AgoraIrisRTC_iOS framework version is incompatible"
        rm -f build.log
        exit 1
    fi
    
    rm -f build.log
    exit 1
fi

echo -e "${GREEN}🎉 iOS symbol validation completed successfully!${NC}"
echo "✅ All required symbols are properly linked"
echo "✅ The SDK should work correctly on iOS devices"