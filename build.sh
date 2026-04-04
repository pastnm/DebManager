#!/bin/bash
# DebManager - Setup & Build Script
# Dev Nasser | NoTimeToChill
# ============================================

set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔══════════════════════════════════════╗"
echo "║        Deb Manager Builder           ║"
echo "║     Dev Nasser | NoTimeToChill       ║"
echo "╚══════════════════════════════════════╝"
echo -e "${NC}"

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ============================================
# OPTION 1: Generate Xcode project with XcodeGen
# ============================================
generate_project() {
    echo -e "${YELLOW}[*] Generating Xcode project with XcodeGen...${NC}"

    if ! command -v xcodegen &> /dev/null; then
        echo -e "${RED}[!] XcodeGen not found. Installing...${NC}"
        brew install xcodegen
    fi

    cd "$PROJECT_DIR"
    xcodegen generate

    echo -e "${GREEN}[✓] DebManager.xcodeproj generated successfully!${NC}"
    echo -e "${CYAN}[*] Open with: open DebManager.xcodeproj${NC}"
}

# ============================================
# OPTION 2: Build IPA for TrollStore
# ============================================
build_trollstore_ipa() {
    echo -e "${YELLOW}[*] Building TrollStore IPA...${NC}"

    cd "$PROJECT_DIR"

    # Clean build
    ARCHIVE_PATH="$PROJECT_DIR/build/DebManager.xcarchive"
    IPA_PATH="$PROJECT_DIR/build/DebManager.tipa"

    echo -e "${CYAN}[*] Building archive...${NC}"
    xcodebuild archive \
        -project DebManager.xcodeproj \
        -scheme DebManager \
        -archivePath "$ARCHIVE_PATH" \
        -sdk iphoneos \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        AD_HOC_CODE_SIGNING_ALLOWED=YES \
        2>&1 | tail -5

    echo -e "${CYAN}[*] Creating .tipa for TrollStore...${NC}"

    # Extract the .app
    APP_PATH="$ARCHIVE_PATH/Products/Applications/DebManager.app"

    if [ ! -d "$APP_PATH" ]; then
        echo -e "${RED}[!] Build failed - .app not found${NC}"
        exit 1
    fi

    # Embed entitlements using ldid (if available) or codesign
    if command -v ldid &> /dev/null; then
        echo -e "${CYAN}[*] Signing with ldid...${NC}"
        ldid -S"$PROJECT_DIR/DebManager/DebManager.entitlements" "$APP_PATH/DebManager"
    else
        echo -e "${YELLOW}[!] ldid not found - using codesign fallback${NC}"
        codesign --force --deep --sign - \
            --entitlements "$PROJECT_DIR/DebManager/DebManager.entitlements" \
            "$APP_PATH"
    fi

    # Create Payload directory and .tipa
    mkdir -p "$PROJECT_DIR/build/Payload"
    cp -r "$APP_PATH" "$PROJECT_DIR/build/Payload/"

    cd "$PROJECT_DIR/build"
    zip -r "DebManager.tipa" Payload/ -x "*.DS_Store"

    # Cleanup
    rm -rf "$PROJECT_DIR/build/Payload"

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✓ TrollStore IPA built successfully ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Output: $IPA_PATH${NC}"
    echo ""
    echo -e "${YELLOW}To install:${NC}"
    echo "  1. Transfer DebManager.tipa to your device"
    echo "  2. Open in TrollStore"
    echo "  3. Tap Install"
    echo ""
}

# ============================================
# Menu
# ============================================
echo "What would you like to do?"
echo ""
echo "  1) Generate Xcode project (xcodegen)"
echo "  2) Build TrollStore .tipa"
echo "  3) Both (generate + build)"
echo ""
read -p "Choose [1/2/3]: " choice

case $choice in
    1)
        generate_project
        ;;
    2)
        if [ ! -f "$PROJECT_DIR/DebManager.xcodeproj/project.pbxproj" ]; then
            echo -e "${YELLOW}[!] No .xcodeproj found - generating first...${NC}"
            generate_project
        fi
        build_trollstore_ipa
        ;;
    3)
        generate_project
        build_trollstore_ipa
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac
