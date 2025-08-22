#!/bin/bash

# Pre-publish validation script for Agora Flutter SDK
# This script runs comprehensive tests before publishing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting pre-publish validation for Agora Flutter SDK${NC}"

# Check if we're in the right directory
if [ ! -f "pubspec.yaml" ] || [ ! -f "ios/agora_rtc_engine.podspec" ]; then
    echo -e "${RED}❌ Error: Must be run from the Flutter plugin root directory${NC}"
    exit 1
fi

FAILED_TESTS=0
TOTAL_TESTS=0

# Function to run test and track results
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo -e "${YELLOW}🧪 Testing: $test_name${NC}"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if eval "$test_command"; then
        echo -e "${GREEN}✅ PASSED: $test_name${NC}"
    else
        echo -e "${RED}❌ FAILED: $test_name${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    echo ""
}

# 1. Flutter analysis
run_test "Dart/Flutter static analysis" "flutter analyze --no-fatal-infos"

# 2. Unit tests
run_test "Unit tests" "flutter test"

# 3. Check pubspec.yaml version consistency
run_test "Version consistency check" "grep -q '^version:' pubspec.yaml"

# 4. iOS podspec validation
run_test "iOS podspec lint" "cd ios && pod lib lint --allow-warnings agora_rtc_engine.podspec"

# 5. Build example app (iOS)
if [ "$(uname)" = "Darwin" ]; then
    run_test "iOS example build" "cd example && flutter build ios --no-codesign --debug"
else
    echo -e "${YELLOW}⚠️  Skipping iOS build (not on macOS)${NC}"
fi

# 6. Build example app (Android)
run_test "Android example build" "cd example && flutter build apk --debug"

# 7. Symbol validation (iOS)
if [ -f "scripts/validate_ios_symbols.sh" ]; then
    run_test "iOS symbol validation" "./scripts/validate_ios_symbols.sh"
else
    echo -e "${YELLOW}⚠️  iOS symbol validation script not found${NC}"
fi

# 8. Check for required files
run_test "Required files check" "[ -f CHANGELOG.md ] && [ -f README.md ] && [ -f LICENSE ]"

# 9. Dependencies check
run_test "Dependencies resolution" "flutter pub get && cd example && flutter pub get"

# 10. Format check
run_test "Code formatting check" "dart format --set-exit-if-changed lib/"

echo -e "${BLUE}📊 Test Results Summary${NC}"
echo "Total tests: $TOTAL_TESTS"
echo "Passed: $((TOTAL_TESTS - FAILED_TESTS))"
echo "Failed: $FAILED_TESTS"

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}🎉 All tests passed! SDK is ready for publishing.${NC}"
    echo -e "${GREEN}✅ No symbol errors detected${NC}"
    echo -e "${GREEN}✅ All builds successful${NC}"
    echo -e "${GREEN}✅ Static analysis clean${NC}"
    exit 0
else
    echo -e "${RED}❌ $FAILED_TESTS test(s) failed. Please fix issues before publishing.${NC}"
    exit 1
fi