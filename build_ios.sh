#!/bin/bash

# Cinema Audio Luxe - iOS Build Setup Script

echo "🎬 Cinema Audio Luxe - iOS Build Setup"
echo "========================================"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check Flutter
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}❌ Flutter not found. Please install Flutter SDK${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Flutter found${NC}"

# Step 1: Clean
echo -e "\n${YELLOW}Step 1: Cleaning...${NC}"
flutter clean
rm -rf ios/Pods ios/Podfile.lock ios/.symlinks ios/Flutter/Flutter.framework ios/Flutter/Flutter.podspec

# Step 2: Get dependencies
echo -e "\n${YELLOW}Step 2: Getting Flutter dependencies...${NC}"
flutter pub get

# Step 3: Pod install
echo -e "\n${YELLOW}Step 3: Installing CocoaPods...${NC}"
cd ios
pod install --repo-update
cd ..

# Step 4: Build
echo -e "\n${YELLOW}Step 4: Building iOS app...${NC}"
flutter build ios --release --no-codesign

if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}✅ Build successful!${NC}"
    echo -e "${GREEN}📱 App ready at: build/ios/iphoneos/Runner.app${NC}"
    echo -e "\n${YELLOW}Next steps:${NC}"
    echo "1. Open in Xcode: open ios/Runner.xcworkspace"
    echo "2. Select your Team ID in Signing & Capabilities"
    echo "3. Connect iPhone XR"
    echo "4. Press Cmd+R to build and run"
else
    echo -e "\n${RED}❌ Build failed${NC}"
    exit 1
fi
