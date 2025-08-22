#!/bin/bash

# Simple script to test if Iris_InitDartApiDL symbol is available
# This validates the fix for the symbol lookup error

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}🔍 Testing Iris_InitDartApiDL symbol availability...${NC}"

# Check if we're in the right directory
if [ ! -f "pubspec.yaml" ]; then
    echo -e "${RED}❌ Run from SDK root directory${NC}"
    exit 1
fi

cd example

# Clean and reinstall
echo "🧹 Cleaning and reinstalling dependencies..."
flutter clean >/dev/null 2>&1
flutter pub get >/dev/null 2>&1

cd ios
rm -rf Pods Podfile.lock >/dev/null 2>&1
pod install >/dev/null 2>&1
cd ..

echo "🏗️ Building iOS app to test symbol resolution..."

# Build and capture output
if flutter build ios --no-codesign --debug 2>&1 | grep -q "Failed to lookup symbol 'Iris_InitDartApiDL'"; then
    echo -e "${RED}❌ FAILED: Iris_InitDartApiDL symbol not found${NC}"
    echo -e "${RED}The symbol lookup error still exists${NC}"
    exit 1
else
    echo -e "${GREEN}✅ SUCCESS: No Iris_InitDartApiDL symbol errors found${NC}"
    echo -e "${GREEN}Symbol is properly linked${NC}"
fi

echo -e "${GREEN}🎉 Symbol validation completed successfully${NC}"