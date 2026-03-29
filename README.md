# OwnMeet

> **Granola for people who care about privacy.** Local-first, bot-free meeting notes powered by [ownscribe](https://github.com/paberr/ownscribe).

OwnMeet is a native macOS menu bar app that silently captures your meetings and phone calls, transcribes them on-device with WhisperX, and produces structured AI notes using Phi-4-mini — all without a bot joining your call, without a cloud subscription, and without any audio or transcripts ever leaving your Mac.

---

## Features

- **No bot, no cloud** — captures system audio directly via Core Audio Taps; works with Zoom, Teams, Meet, FaceTime, anything
- **Menu bar app** — lives quietly in your menu bar, always one click away
- **Live transcript** — streaming transcript while recording (with ownscribe patches applied)
- **Raw notes notepad** — jot bullet points during the call; the AI uses them to anchor your summary
- **Post-meeting editor** — edit, regenerate (with a different template), and share notes
- **Meeting library** — searchable archive of all past sessions; ask natural-language questions across them
- **Calendar integration** — shows today's events, optionally auto-prompts recording when a meeting starts
- **Templates** — Meeting, Lecture, Brief (built-in); extensible via ownscribe's TOML config
- **Export** — Markdown, PDF, JSON, or Share Sheet

### Privacy model
- All audio → WhisperX runs entirely on your Mac
- LLM summarization: Phi-4-mini by default (local); optionally Ollama or any OpenAI-compatible host
- No telemetry, no analytics, no accounts
- All data stored in `~/ownscribe/` — yours forever

---

## Requirements

- macOS 14.2 or later (Apple Silicon or Intel)
- Xcode 15+ / Swift 5.9+ (to build from source)
- [uv](https://github.com/astral-sh/uv) (`brew install uv`) — provides `uvx ownscribe`
- ffmpeg (`brew install ffmpeg`)

---

## Quick Start

### 1. Install dependencies

```bash
bash scripts/install_ownscribe.sh
# Optional: pre-download Whisper + Phi-4-mini models (saves time on first recording)
bash scripts/install_ownscribe.sh --warmup
```

### 2. Build OwnMeet

```bash
bash scripts/build_app.sh              # Debug build
bash scripts/build_app.sh --install    # Release build → /Applications/OwnMeet.app
```

Or open `OwnMeet/OwnMeet.xcodeproj` in Xcode and press ⌘R.

### 3. Grant permissions

On first launch, OwnMeet will guide you through:
- **Screen Recording** — required for system audio capture
- **Microphone** — to record your voice
- **Calendar** — optional, for showing today's meetings

### 4. Record a meeting

- Click the waveform icon in your menu bar → **Start Recording**, or press **⌘⇧R**
- OwnMeet records all audio from your Mac (and optionally your mic)
- When the call ends, click **Stop & Summarize** (or press ⌘⇧R again)
- Structured notes appear in the library within ~30 seconds

---

## Architecture

```
OwnMeet.app (Swift 6 / SwiftUI)
├── MenuBarExtra — always-accessible recording controls
├── LibraryView — meeting list + calendar events + NL search
├── LiveRecordingView — split: live transcript / raw notes
├── SessionView — past session: editable notes / transcript / user notes
├── SettingsView — tabbed settings for all ownscribe options
└── OnboardingView — first-launch wizard

OwnScribeProcessManager
└── spawns `uvx ownscribe` subprocess
    ├── reads stdout JSON lines (patched ownscribe) or plain text (stock)
    ├── sends SIGINT to stop gracefully
    └── reloads SessionStore on completion

SessionStore
└── watches ~/ownscribe/ via GCD DispatchSource
    └── parses YYYY-MM-DD_HHMMSS directories into Session objects
```

See [`Plan.md`](Plan.md) for the full architecture and roadmap.

---

## ownScribe Patches

OwnMeet works with stock ownscribe but gains extra features with four small upstream patches.
See [`patches/ownscribe_patches.py`](patches/ownscribe_patches.py) for the implementation guide.

| Flag | Effect |
|---|---|
| `--json-progress` | Emits structured JSON events to stdout (progress, errors, session path) |
| `--stream-transcript` | Streams transcript chunks as JSON lines during recording |
| `--user-notes <file>` | Injects a Markdown notes file into the summarization prompt |
| `--pid-file <path>` | Writes PID for reliable SIGINT from the Swift app |

---

## Distribution

OwnMeet cannot be distributed via the Mac App Store (requires subprocess spawning, which needs no-sandbox entitlement). Distribute via:

- **Homebrew cask** — `brew install --cask ownmeet` (once published)
- **Direct DMG** — build with `bash scripts/build_app.sh --release` and notarize

---

## License

MIT — same as ownscribe upstream.

---

*Built with ❤️ on top of [paberr/ownscribe](https://github.com/paberr/ownscribe), WhisperX, and Phi-4-mini.*
