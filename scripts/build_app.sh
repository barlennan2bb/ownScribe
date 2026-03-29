#!/usr/bin/env bash
# build_app.sh — Build OwnMeet.app from source using XcodeGen + xcodebuild.
# Usage:
#   bash scripts/build_app.sh              # Debug build
#   bash scripts/build_app.sh --release    # Release build
#   bash scripts/build_app.sh --install    # Release build + copy to /Applications
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/OwnMeet"
BUILD_DIR="$PROJECT_DIR/build"
CONFIG="Debug"
INSTALL=false

GREEN='\033[0;32m'
NC='\033[0m'
log() { echo -e "${GREEN}[build]${NC} $*"; }

# Parse args
for arg in "$@"; do
    case $arg in
        --release) CONFIG="Release" ;;
        --install) INSTALL=true; CONFIG="Release" ;;
    esac
done

# ─── 1. XcodeGen ────────────────────────────────────────────────────────────
log "Generating Xcode project…"
if ! command -v xcodegen &>/dev/null; then
    log "Installing xcodegen via Homebrew…"
    brew install xcodegen
fi
(cd "$PROJECT_DIR" && xcodegen generate --spec project.yml --project .)
log "OwnMeet.xcodeproj generated."

# ─── 2. xcodebuild ──────────────────────────────────────────────────────────
log "Building OwnMeet ($CONFIG)…"
xcodebuild \
    -project "$PROJECT_DIR/OwnMeet.xcodeproj" \
    -scheme OwnMeet \
    -configuration "$CONFIG" \
    -derivedDataPath "$BUILD_DIR" \
    -destination "platform=macOS" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    | xcpretty 2>/dev/null || true

APP_PATH="$BUILD_DIR/Build/Products/$CONFIG/OwnMeet.app"

if [[ ! -d "$APP_PATH" ]]; then
    echo "Build failed — OwnMeet.app not found at $APP_PATH"
    exit 1
fi

log "Build succeeded: $APP_PATH"

# ─── 3. Ad-hoc sign ─────────────────────────────────────────────────────────
log "Ad-hoc signing…"
codesign --force --deep --sign - "$APP_PATH"
log "Signed."

# ─── 4. Install ─────────────────────────────────────────────────────────────
if $INSTALL; then
    log "Copying to /Applications…"
    cp -R "$APP_PATH" /Applications/OwnMeet.app
    log "Installed: /Applications/OwnMeet.app"
    open /Applications/OwnMeet.app
fi

log "Done. App: $APP_PATH"
