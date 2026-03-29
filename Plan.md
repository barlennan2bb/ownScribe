# OwnMeet — Granola-like Meeting Recorder for macOS
> A local-first, bot-free meeting notes app built on top of ownScribe OSS

---

## What We're Building

A native macOS app that silently captures system audio and microphone during meetings and phone calls, transcribes speech locally (no cloud), and uses a local LLM to produce structured, editable notes — identical in workflow to Granola but 100% private, 100% local, and fully open source.

**Core differentiator vs. Granola:** Everything runs on-device. No audio or transcripts ever leave your Mac. No subscription. No bots joining calls.

**Foundation:** [ownScribe v0.10.0](https://github.com/paberr/ownscribe) provides the entire audio capture → transcription → summarization pipeline as a Python CLI. We wrap it in a native SwiftUI app.

---

## Current State of ownScribe (What We Get for Free)

- System audio capture via Core Audio Taps (macOS 14.2+, no virtual drivers)
- Microphone capture simultaneously with `--mic`
- WhisperX transcription (word-level timestamps, multilingual)
- Speaker diarization via pyannote (optional, needs HF token)
- Local LLM summarization — Phi-4-mini built-in; Ollama/LM Studio supported
- Summarization templates: `meeting`, `lecture`, `brief`, plus custom TOML templates
- Natural-language search across all past meetings (`ownscribe ask`)
- Silence auto-stop (configurable)
- Pipeline saved to `~/ownscribe/YYYY-MM-DD_HHMMSS/` as Markdown or JSON
- Resume failed/partial sessions (`ownscribe resume`)

---

## What We Need to Build

### 1. Native macOS SwiftUI App (the "shell")

The Swift app manages everything the user sees and touches. ownScribe runs as a managed background subprocess.

**Components:**
- **Menu bar icon** — always-available recording controls (start/stop, mute mic, status indicator)
- **Main window** — meeting library, live transcript view, notes editor, settings
- **Session manager** — spawns/monitors the ownScribe process, streams its output
- **IPC bridge** — reads ownScribe stdout/stderr in real-time; writes config on behalf of the user

### 2. Calendar Integration (EventKit)

- Read Google Calendar / macOS Calendar events via EventKit
- Show upcoming meetings in the app, detect when one starts
- Auto-prompt (or auto-start) recording when a calendar event begins
- Tag saved sessions with the event title, attendees, and calendar metadata

### 3. Live Transcript View

ownScribe currently writes transcript only after recording stops. We extend it to stream partial Whisper results during recording using WhisperX's streaming/chunked mode, piped to the Swift app via stdout JSON lines.

- Rolling live transcript panel visible during recording
- Speaker labels when diarization is enabled
- "Transcript follows audio" — click a line to seek to that timestamp in playback

### 4. In-Meeting Raw Notes Notepad

During a meeting, users type raw bullet points and context (Granola-style). These are passed to ownScribe's summarization pipeline as a `--user-notes` file, letting the LLM anchor the summary to what the user cared about.

- Minimalist notepad alongside the live transcript
- Markdown-aware (headings auto-become template sections)
- Persisted per-session to `user_notes.md` in the session directory

### 5. Post-Meeting Notes Editor

After ownScribe finishes summarizing:
- Display AI-enhanced notes in a split view (raw transcript on left, structured notes on right)
- User-written notes highlighted differently from AI-generated additions (black vs. grey — Granola's exact model)
- "Regenerate with different template" button
- In-line editing of the final notes

### 6. Meeting Library

- List of all past sessions sorted by date
- Search bar wired to `ownscribe ask` for natural-language queries across all meetings
- Filter by date range, template type, or keywords
- Click any session to open it in the notes editor with full transcript and audio playback

### 7. Phone Call Capture

For phone calls (FaceTime Audio, regular calls via iPhone Continuity):
- Use microphone-only mode (`ownscribe --device`) targeting the default mic
- Or capture system audio when calls route through Mac speakers
- One-tap quick-capture button in menu bar for ad-hoc calls

### 8. Export & Share

- Copy summary to clipboard (plain text or Markdown)
- Share via macOS Share Sheet (Mail, Messages, Notes, Slack)
- Export as `.md`, `.pdf`, or `.json`
- Optional: Slack webhook integration (post summary to a channel)

### 9. Settings UI

- Whisper model selector (tiny → large-v3) with disk/speed tradeoffs shown
- LLM backend selector (local Phi-4-mini / Ollama / LM Studio / OpenAI-compatible)
- Speaker diarization toggle + HuggingFace token entry
- Default template selector
- Audio device picker (mic + system audio)
- Output directory
- Silence timeout slider
- Privacy: opt-in telemetry (default off), HF telemetry (default off)

---

## Architecture

```
┌─────────────────────────────────────────────┐
│              OwnMeet.app (Swift/SwiftUI)     │
│                                             │
│  MenuBarController   MainWindowController   │
│  CalendarManager     TranscriptStreamer      │
│  SessionStore        NotesEditor            │
│  SettingsManager     ExportManager          │
│                                             │
│         OwnScribeProcessManager             │
│    (spawns ownscribe, reads stdout/stderr)  │
└──────────────────┬──────────────────────────┘
                   │ subprocess + stdout streaming
                   ▼
┌─────────────────────────────────────────────┐
│           ownscribe (Python/uv)             │
│                                             │
│  CoreAudio Swift helper  WhisperX           │
│  pyannote diarization    Phi-4-mini LLM     │
│  TOML config             ~/ownscribe/ store │
└─────────────────────────────────────────────┘
```

**Key design choice:** The Swift app does NOT re-implement any audio/ML logic. It purely manages ownScribe as a subprocess and provides the UI layer. This keeps ML dependencies out of the Swift build and means ownScribe upstream improvements are inherited automatically.

---

## Tech Stack

| Layer | Technology |
|---|---|
| macOS UI | Swift 6, SwiftUI, AppKit (menu bar) |
| Calendar | EventKit framework |
| Audio permissions | AVFoundation, ScreenCaptureKit |
| IPC | NSTask + stdout streaming (JSON lines) |
| Transcription | WhisperX (via ownScribe) |
| Diarization | pyannote.audio (via ownScribe) |
| LLM summarization | llama.cpp / Phi-4-mini (via ownScribe) |
| Config | TOML (ownScribe's existing config) |
| Storage | `~/ownscribe/` (ownScribe's existing layout) |
| Dependency mgmt | uv (Python), SPM (Swift) |

---

## Implementation Phases

### Phase 1 — Foundation (Weeks 1–2)
- Xcode project scaffold (SwiftUI app + menu bar)
- `OwnScribeProcessManager`: spawn `ownscribe`, capture stdout/stderr, handle process lifecycle
- Install ownScribe via `uv` on first launch if not present
- Basic menu bar: Start Recording / Stop Recording / Status
- Read existing `~/ownscribe/` sessions and display as a list

### Phase 2 — Live Transcript (Weeks 3–4)
- Patch ownScribe (or add a `--stream-transcript` flag) to emit partial transcript JSON lines to stdout during recording
- `TranscriptStreamer` in Swift subscribes to stdout and appends lines in real time to the UI
- Live transcript panel in the main window

### Phase 3 — Calendar + Auto-Start (Week 5)
- EventKit integration: request calendar access, list upcoming events
- "Meetings Today" view in the main window
- Notification + auto-start prompt when a calendar event begins
- Tag completed sessions with the matched calendar event

### Phase 4 — Notes Editor + Post-Processing UI (Weeks 6–7)
- In-meeting raw notes notepad (persisted to `user_notes.md`)
- Pass `user_notes.md` to ownScribe summarization (`--user-notes` flag — requires small ownScribe patch)
- Post-meeting notes view: split transcript / enhanced notes
- Re-generate and template-switch buttons
- In-line note editing (persists edits back to the Markdown file)

### Phase 5 — Meeting Library + Search (Week 8)
- Full session library UI with search
- Wire search to `ownscribe ask` subprocess call
- Date/template filters
- Audio playback with transcript sync (click line → seek)

### Phase 6 — Export, Share & Phone Calls (Weeks 9–10)
- Share Sheet integration
- PDF/Markdown/JSON export
- Slack webhook (optional)
- Quick-capture menu bar button for phone calls (mic-only mode)
- FaceTime Audio / Continuity detection

### Phase 7 — Polish & Distribution (Weeks 11–12)
- Settings UI (all ownScribe config exposed via SwiftUI forms)
- First-launch onboarding: permissions walkthrough, model warmup
- Automatic ownScribe update check
- App signing + notarization
- Homebrew cask formula
- README and documentation

---

## Required ownScribe Patches (Upstream PRs)

These are small additions to ownScribe needed to support the GUI layer:

1. **`--stream-transcript`** — emit partial Whisper chunks as JSON lines to stdout during recording
2. **`--user-notes <file>`** — inject a user-notes Markdown file into the summarization prompt
3. **`--json-progress`** — emit structured JSON progress events (instead of rich TUI output) so the Swift app can render its own progress UI
4. **`--pid-file <path>`** — write ownScribe's PID to a file so the manager can reliably signal it

All four are non-breaking additions. Intent is to submit these as PRs to `paberr/ownscribe`.

---

## macOS Permissions Required

| Permission | Why |
|---|---|
| Microphone | Record user's voice |
| Screen Recording | System audio capture (Core Audio Tap) |
| Calendars | Read calendar events for auto-start |
| Accessibility | (optional) detect active app for context |

---

## Privacy Model

- All audio processing is local (Core Audio → WhisperX on-device)
- No audio files uploaded anywhere
- LLM summarization: local by default (Phi-4-mini); user can optionally configure Ollama or an OpenAI-compatible host
- When using an external LLM host: only the text transcript is sent, never audio
- No telemetry by default
- All data stored in `~/ownscribe/` — user owns it entirely

---

## Repository Structure (Proposed)

```
ownScribe/
├── OwnMeet/                   # Swift/SwiftUI Xcode project
│   ├── App/
│   ├── MenuBar/
│   ├── Views/
│   │   ├── LibraryView.swift
│   │   ├── SessionView.swift
│   │   ├── TranscriptView.swift
│   │   ├── NotesEditorView.swift
│   │   └── SettingsView.swift
│   ├── Models/
│   ├── Services/
│   │   ├── OwnScribeProcessManager.swift
│   │   ├── CalendarManager.swift
│   │   ├── TranscriptStreamer.swift
│   │   └── ExportManager.swift
│   └── OwnMeet.xcodeproj
├── patches/                   # ownScribe upstream patches (git format-patch)
├── scripts/
│   ├── install_ownscribe.sh   # ensures ownscribe + uv are installed
│   └── build.sh
├── Plan.md                    # this file
└── README.md
```

---

## Open Questions / Decisions Needed

1. **Whisper model default** — `base` (fast, ~145MB) vs `small` (better quality, ~466MB). Recommend `small` as default for meeting use.
2. **Diarization default** — off by default (requires HF token); expose as easy toggle with token entry in onboarding.
3. **LLM default** — Phi-4-mini local is best for privacy. Expose Ollama/OpenAI as power-user options.
4. **App name** — "OwnMeet" is a placeholder. Alternatives: MeetScribe, LocalNotes, PrivateMeet.
5. **Minimum macOS** — macOS 14.2 required for system audio capture (Core Audio Taps). This aligns with ownScribe's own requirement.
6. **Distribution** — Homebrew cask is the path of least resistance; Mac App Store requires sandboxing which conflicts with subprocess spawning.
