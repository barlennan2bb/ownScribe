# OwnMeet Release Notes

---

## v1.0.0 — 2026-03-29

Initial release of **OwnMeet**: a native macOS menu bar app that wraps
[ownscribe](https://github.com/paberr/ownscribe) with a Granola-like UI for
local-first, bot-free meeting notes.

### What it does

- Captures system audio and microphone via ownscribe's Core Audio Tap pipeline
  (macOS 14.2+, no virtual audio drivers required)
- Transcribes speech locally with WhisperX (never leaves your Mac)
- Summarizes with Phi-4-mini LLM (local by default; Ollama/OpenAI-compatible optional)
- Shows AI-structured notes (Summary, Key Points, Action Items, Decisions) in a
  native split-pane window
- Stores everything in `~/ownscribe/` alongside ownscribe's own output

### Features

**Menu bar app**
- Waveform icon lives in the menu bar; no Dock icon (LSUIElement)
- Start/Stop recording with ⌘⇧R from anywhere
- Mute mic toggle with ⌘⇧M during recording
- Status indicator: Ready → Recording → Summarizing → Done ✓
- Elapsed recording timer in the menu dropdown

**Library window**
- Lists all past sessions (ownscribe's `YYYY-MM-DD_HHMM` and
  `YYYY-MM-DD_HHMM_slug-title` directory formats both supported)
- Natural-language search powered by `ownscribe ask` (prefix query with `?` or `ask:`)
- Session row shows title derived from summary headline, date, and duration
- Context menu: Copy Summary, Export, Delete

**Calendar integration**
- Reads macOS Calendar via EventKit
- Displays today's upcoming events in the sidebar with color-coded calendar strips
- "Record" button appears inline for events starting within 2 minutes
- Notification banner fires 2 minutes before any scheduled event
  (banner includes "Start Recording" action button)
- Optional fully-automatic mode: recording starts silently without user prompt
  (Settings → Calendar → "Auto-prompt recording when a meeting starts")

**Live recording view**
- Split pane: left = live transcript stream (requires ownscribe patch, falls back
  to animated placeholder with stock ownscribe); right = raw notes notepad
- Notes typed during the call are saved to `user_notes.md` alongside the recording
  and passed to the LLM to anchor the summary

**Session detail view**
- Three tabs: Notes (AI-enhanced, editable) / Transcript (read-only) / Your Notes
- In-line editing: edit the summary markdown, click Save (⌘S) to persist to disk
- Regenerate with a different template (Meeting, Lecture, Brief) via Regenerate menu
- Copy to clipboard (plain text or markdown)
- Export to Markdown, Transcript (.txt), JSON, or PDF
- macOS Share Sheet integration

**Settings (⌘,)**
- Audio: system audio toggle, mic toggle, device name, silence timeout, output dir
- Transcription: Whisper model selector (tiny → large-v3 with disk sizes shown),
  language override, speaker diarization toggle + HuggingFace token
- Summarization: default template, LLM backend (local/Ollama/OpenAI-compatible),
  model name, host URL, warmup button
- Calendar: access grant button, auto-start toggle
- About: ownscribe version, links

**Onboarding**
- 5-step first-launch wizard: Welcome → Permissions → Dependencies → Model Warmup → Done
- Checks for Microphone, Screen Recording, and Calendar permissions with Grant buttons
- Installs `uv` via Homebrew if missing
- Runs `ownscribe warmup` to pre-download Whisper and Phi-4-mini models

### Architecture

```
OwnMeet.app (Swift 6 / SwiftUI, macOS 14.2+)
└── OwnScribeProcessManager
    └── spawns: uvx ownscribe [args]
        ├── stdout: JSON events (patched) or plain-text fallback (stock)
        └── exits: reloads SessionStore

SessionStore
└── watches ~/ownscribe/ via GCD DispatchSource (DispatchSourceFileSystemObject)
    └── YYYY-MM-DD_HHMM and YYYY-MM-DD_HHMM_slug-* directories
```

### Build

Requires: macOS 14.2+, Xcode 15+ (Swift 6.2), XcodeGen, `uv` (brew install uv), ffmpeg

```bash
cd OwnMeet && xcodegen generate && cd ..
xcodebuild -project OwnMeet/OwnMeet.xcodeproj -scheme OwnMeet \
  -configuration Release -destination "platform=macOS" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
```

Or use the convenience script:
```bash
bash scripts/build_app.sh --install
```

### Screen Recording permission

ownscribe captures system audio via a Swift helper binary. Grant Screen Recording
to it once in System Settings:

```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
```

Click `+` → navigate to `~/.local/share/ownscribe/bin/` → select `ownscribe-audio` → ON.

This is a one-time step. The permission persists across reboots.

### ownscribe upstream patches (planned)

Four flags have been designed for submission as PRs to `paberr/ownscribe`.
Until merged, OwnMeet works with stock ownscribe v0.10.0; the live transcript
panel activates automatically once the patches land.

| Flag | Effect |
|---|---|
| `--json-progress` | Structured JSON events to stdout (progress, session path, errors) |
| `--stream-transcript` | Transcript chunks as JSON lines during recording |
| `--user-notes <file>` | Inject user notes into the LLM summarization prompt |
| `--pid-file <path>` | Write PID for reliable SIGINT from the GUI |

See `patches/ownscribe_patches.py` for full implementation details.

### Known limitations

- **No App Store distribution**: subprocess spawning requires disabling the sandbox,
  which is incompatible with Mac App Store. Distribute via Homebrew cask or direct DMG.
- **Live transcript**: shows "Waiting for transcript..." with stock ownscribe; activates
  fully once upstream patch `--stream-transcript` is merged.
- **Mic mute**: SIGUSR1-based mute requires ownscribe to handle the signal; currently
  sends the signal but ownscribe ignores it until patched.
- **Screen Recording re-grant**: if ownscribe auto-updates and the `ownscribe-audio`
  binary changes signature, the permission may need to be re-granted once.

### Bug fixes applied during development

- Fixed ownscribe flag crash: stock v0.10.0 rejects `--stream-transcript`,
  `--json-progress`, `--pid-file` with "No such option" — removed until patches land
- Fixed session directory detection: ownscribe uses `YYYY-MM-DD_HHMM` (4-digit time),
  not `YYYY-MM-DD_HHMMSS` (6-digit) as documented — regex and date parser corrected
- Fixed slug directory filtering: sessions with auto-generated slug suffixes like
  `2026-03-29_0752_device-malfunction-urgent-bed-rest` were excluded — regex fixed
- Fixed mic default: `captureMicrophone` now defaults to `true`; previously only
  system audio was captured, producing silent recordings until Screen Recording
  permission was granted
- Fixed inverted mic device condition: `--device <name>` was passed when device name
  was empty, and skipped when it was set — condition was inverted
- Fixed force unwrap: `NSApp.keyWindow!` in ExportManager replaced with safe `guard let`

---

*Built on top of [paberr/ownscribe](https://github.com/paberr/ownscribe) (MIT),
WhisperX, and Phi-4-mini.*
