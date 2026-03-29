#!/usr/bin/env bash
# install_ownscribe.sh — Ensure uv and ownscribe are available on this Mac.
# Run this once before launching OwnMeet for the first time.
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()   { echo -e "${GREEN}[install]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
error() { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }

# ─── 1. Check Homebrew ──────────────────────────────────────────────────────
log "Checking for Homebrew…"
if ! command -v brew &>/dev/null; then
    warn "Homebrew not found. Installing…"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
log "Homebrew: $(brew --version | head -1)"

# ─── 2. Install uv (provides uvx) ───────────────────────────────────────────
log "Checking for uv…"
if ! command -v uvx &>/dev/null; then
    log "Installing uv via Homebrew…"
    brew install uv
else
    log "uv: $(uvx --version 2>&1 | head -1)"
fi

# ─── 3. Install ffmpeg (required by WhisperX) ───────────────────────────────
log "Checking for ffmpeg…"
if ! command -v ffmpeg &>/dev/null; then
    log "Installing ffmpeg via Homebrew…"
    brew install ffmpeg
else
    log "ffmpeg: $(ffmpeg -version 2>&1 | head -1)"
fi

# ─── 4. Verify ownscribe runs ────────────────────────────────────────────────
log "Verifying ownscribe (may download on first run)…"
uvx ownscribe --version && log "ownscribe: OK" || warn "ownscribe not yet cached; will download on first use."

# ─── 5. Warmup models (optional) ────────────────────────────────────────────
if [[ "${1:-}" == "--warmup" ]]; then
    log "Running ownscribe warmup (downloads Whisper + Phi-4-mini)…"
    log "This may take several minutes depending on your connection."
    uvx ownscribe warmup
    log "Warmup complete."
else
    echo ""
    echo "  Run with --warmup to pre-download models:"
    echo "    bash scripts/install_ownscribe.sh --warmup"
fi

# ─── 6. Screen Recording reminder ───────────────────────────────────────────
echo ""
log "Almost done! Grant Screen Recording permission to capture system audio:"
echo "  System Settings → Privacy & Security → Screen Recording → enable OwnMeet"
echo ""
log "Or open directly:"
echo "  open 'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture'"
echo ""
log "Installation complete. Launch OwnMeet.app to get started."
