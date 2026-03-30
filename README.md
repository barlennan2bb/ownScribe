# OwnMeet

> **Granola for people who care about privacy.**  
> Local-first, bot-free meeting notes — entirely on your Mac.

OwnMeet is a native macOS menu bar app that silently records your meetings and
phone calls, transcribes speech on-device with WhisperX, and produces structured
AI notes using a local LLM — no bot joining your call, no cloud subscription,
no audio or text ever leaving your machine.

It is a GUI shell built on top of the excellent open-source CLI
[ownscribe](https://github.com/paberr/ownscribe), adding a polished native
interface, calendar integration, and automated recording triggers.

---

## Why OwnMeet?

| | OwnMeet | Granola / Otter / Fireflies |
|---|---|---|
| Bot joins your call | ✗ Never | ✓ Always visible |
| Audio leaves your Mac | ✗ Never | ✓ Sent to cloud |
| Works with headphones | ✓ Yes | Sometimes |
| Subscription required | ✗ Free/OSS | $14–$20/month |
| Works offline | ✓ Fully | ✗ No |
| Customizable LLM | ✓ Yes | ✗ No |

OwnMeet uses macOS **Core Audio Taps** — introduced in macOS 14.2 — to intercept
audio at the OS mixer level. This means it captures any audio playing through
your Mac (Zoom, Teams, Meet, FaceTime, YouTube, phone calls via Continuity)
regardless of your output device, including wired or wireless headphones.

---

## Features

### Recording
- **One-click or one-keystroke recording** — Start/Stop with ⌘⇧R from anywhere
- **System audio + microphone** — captures both sides of a call simultaneously
- **Headphone-friendly** — Core Audio Taps work regardless of audio output device
- **Silence auto-stop** — recording ends automatically after configurable silence
- **Mic mute** — toggle microphone mute mid-recording with ⌘⇧M

### Transcription & Notes
- **WhisperX on-device** — fast, accurate speech-to-text, never sent to a server
- **Speaker diarization** — optional speaker identification (requires HuggingFace token)
- **AI meeting notes** — Phi-4-mini generates structured notes locally by default
- **Templates** — Meeting (Summary, Key Points, Action Items, Decisions), Lecture,
  Brief; define custom templates in ownscribe's TOML config
- **Raw notes notepad** — type bullet points during the call; they anchor the AI summary
- **Editable notes** — edit, regenerate with a different template, and save back to disk

### Calendar Integration
- **Today's meetings** in the sidebar with color-coded calendar strips
- **2-minute warning** — macOS notification banner fires before each scheduled event
  with a "Start Recording" action button
- **Auto-start mode** — recording begins silently the moment a meeting starts
  (opt-in, Settings → Calendar)

### Library & Search
- **Full session history** browsable in the sidebar
- **Natural-language search** — type `? what did we decide about pricing?` to query
  across all past sessions using `ownscribe ask`
- **Export** — Markdown, plain text, JSON, PDF, or macOS Share Sheet

### Privacy
- All audio processing runs on your Mac; nothing is transmitted
- LLM: Phi-4-mini local by default; Ollama or any OpenAI-compatible host optional
- No accounts, no telemetry, no analytics
- All data stored in `~/ownscribe/` — plain files, always accessible

---

## Requirements

- **macOS 14.2 or later** (Apple Silicon or Intel) — Core Audio Taps require 14.2+
- **Xcode 15+ / Swift 6** — to build from source
- **[uv](https://github.com/astral-sh/uv)** — `brew install uv` — runs ownscribe via `uvx`
- **ffmpeg** — `brew install ffmpeg` — required by WhisperX

---

## Installation

### Step 1 — Install dependencies

```bash
bash scripts/install_ownscribe.sh
```

This script checks for Homebrew, installs `uv` and `ffmpeg` if missing, and
verifies ownscribe is reachable via `uvx`.

Optionally pre-download the AI models now (~3 GB total) to avoid a delay on
your first recording:

```bash
bash scripts/install_ownscribe.sh --warmup
```

### Step 2 — Grant Screen Recording to the audio helper

ownscribe captures system audio through a native Swift helper. Open Screen
Recording settings and add it once:

```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
```

Click **`+`** → press **⌘⇧G** → paste `~/.local/share/ownscribe/bin/` →
select **`ownscribe-audio`** → toggle **ON**.

This is a one-time step that persists across reboots.

### Step 3 — Build OwnMeet

```bash
bash scripts/build_app.sh --install   # builds Release → /Applications/OwnMeet.app
```

Or open `OwnMeet/OwnMeet.xcodeproj` in Xcode (generated via XcodeGen) and
press **⌘R**.

### Step 4 — First launch

The onboarding wizard walks through:
1. Microphone and Calendar permissions
2. Dependency check (installs `uv` via Homebrew if missing)
3. Model warmup (downloads WhisperX + Phi-4-mini if not done in Step 1)

---

## Usage

### Recording a meeting

1. Join your Zoom / Teams / Meet / FaceTime call as normal
2. Press **⌘⇧R** (or click the waveform `〜` in the menu bar → Start Recording)
3. A live transcript pane opens — type any notes in the right-hand notepad
4. When the call ends, press **⌘⇧R** again (or click Stop)
5. OwnMeet transcribes and summarizes in the background (~30–60 seconds)
6. Your session appears in the library with structured notes

### Recording a phone call

For calls routed through your Mac (FaceTime Audio, iPhone Continuity calls):
- OwnMeet captures the system audio channel automatically
- For a mic-only capture of a traditional phone call, use the terminal:
  ```bash
  uvx ownscribe --mic
  ```

### Viewing and editing notes

- Click any session in the sidebar to open it
- **Notes tab** — AI-generated summary; fully editable; ⌘S to save
- **Transcript tab** — full timestamped transcript with speaker labels (if diarization enabled)
- **Your Notes tab** — raw notes you typed during the call
- **Regenerate** — re-summarize with a different template (Meeting / Lecture / Brief)
- **Export** — Markdown, JSON, PDF, or Share Sheet

### Searching across meetings

In the search bar, prefix your query with `?` or `ask:` to invoke
`ownscribe ask` across all past sessions:

```
? what did we decide about the API design?
ask: action items from last week
```

### Calendar auto-start

To enable automatic recording when a scheduled meeting begins:
- Settings (⌘,) → Calendar tab → toggle **"Auto-prompt recording when a meeting starts"**

With this ON, OwnMeet silently starts recording the moment a calendar event
enters its 2-minute window. With it OFF (default), a notification banner
appears with a **Start Recording** button.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   OwnMeet.app                           │
│  (Swift 6 / SwiftUI / MenuBarExtra / macOS 14.2+)       │
│                                                         │
│  MenuBarView          LibraryView                       │
│  ├── status / timer   ├── session list (sidebar)        │
│  └── start/stop       ├── calendar events               │
│                        └── NL search                    │
│  LiveRecordingView    SessionView                       │
│  ├── live transcript  ├── Notes (editable markdown)     │
│  └── raw notes pad    ├── Transcript (timestamped)      │
│                        └── Your Notes                   │
│  SettingsView         OnboardingView                    │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │           Services (all @MainActor)              │  │
│  │  OwnScribeProcessManager  SessionStore           │  │
│  │  CalendarManager          NotificationManager    │  │
│  │  ExportManager            OwnScribeInstaller     │  │
│  └──────────────────────────────────────────────────┘  │
└──────────────────────────┬──────────────────────────────┘
                           │ NSTask (subprocess)
                           ▼
┌─────────────────────────────────────────────────────────┐
│              ownscribe (Python / uvx)                   │
│  ownscribe-audio (Swift)  WhisperX     Phi-4-mini       │
│  └── Core Audio Tap       └── STT      └── LLM          │
│  ~/ownscribe/YYYY-MM-DD_HHMM[-slug]/                    │
│  ├── recording.wav   ├── transcript.md  ├── summary.md  │
│  └── user_notes.md   └── ownmeet.json                   │
└─────────────────────────────────────────────────────────┘
```

**Key design principle:** OwnMeet contains zero audio/ML code. It is a pure UI
shell. All heavy lifting — audio capture, speech-to-text, LLM inference — is
done by ownscribe. This means ownscribe improvements flow through automatically,
and the app stays lightweight and fast to build.

### Data flow

```
Core Audio Tap → recording.wav → WhisperX → transcript.md
                                                    ↓
                              user_notes.md → Phi-4-mini → summary.md
                                                    ↓
                                           OwnMeet library
```

### Source layout

```
OwnMeet/
├── Sources/OwnMeet/
│   ├── OwnMeetApp.swift              @main App entry point
│   ├── MenuBar/MenuBarView.swift     Menu bar dropdown
│   ├── Models/
│   │   ├── Session.swift             One recording session
│   │   ├── TranscriptLine.swift      One spoken segment
│   │   └── AppSettings.swift         UserDefaults-backed settings
│   ├── Services/
│   │   ├── OwnScribeProcessManager   Subprocess lifecycle + stdout parsing
│   │   ├── SessionStore              FSEvents watcher on ~/ownscribe/
│   │   ├── CalendarManager           EventKit integration
│   │   ├── NotificationManager       UNUserNotificationCenter delegate
│   │   ├── ExportManager             Clipboard / Share Sheet / file export
│   │   └── OwnScribeInstaller        Dependency check + warmup
│   └── Views/
│       ├── LibraryView.swift
│       ├── LiveRecordingView.swift
│       ├── SessionView.swift
│       ├── SettingsView.swift
│       └── OnboardingView.swift
├── Resources/
│   ├── Info.plist                    LSUIElement=YES, privacy strings
│   └── OwnMeet.entitlements          No sandbox (required for subprocess)
└── project.yml                       XcodeGen spec
```

---

## Configuration

All settings are accessible in the app (⌘,). They are also stored as `UserDefaults`
and map directly to ownscribe's CLI flags. Key defaults:

| Setting | Default | Notes |
|---|---|---|
| Whisper model | `small` | ~466 MB; `large-v3` for best accuracy |
| LLM backend | Local (Phi-4-mini) | ~2.4 GB; Ollama/OpenAI-compatible optional |
| Capture microphone | ON | Captures your voice |
| Capture system audio | ON | Captures call audio, YouTube, etc. |
| Silence timeout | 5 min | Auto-stops recording |
| Default template | Meeting | Meeting / Lecture / Brief |
| Speaker diarization | OFF | Requires HuggingFace token |

You can also edit ownscribe's own config file directly for advanced options
(custom templates, Ollama model names, output format):

```bash
uvx ownscribe config
```

---

## ownscribe Upstream Patches

OwnMeet works fully with stock **ownscribe v0.10.0**. Four optional patches
have been designed for contribution upstream. When merged, they unlock:

| Patch | Unlocks in OwnMeet |
|---|---|
| `--json-progress` | Real-time status messages in the UI |
| `--stream-transcript` | Live transcript panel fills during recording |
| `--user-notes <file>` | Your notepad notes are injected into the LLM prompt |
| `--pid-file <path>` | Reliable stop signal (currently uses process.interrupt()) |

See [`patches/ownscribe_patches.py`](patches/ownscribe_patches.py) for the
complete implementation guide to submit as PRs to `paberr/ownscribe`.

---

## Roadmap

### Near-term (next sprint)

- **Submit ownscribe upstream patches** — `--json-progress`, `--stream-transcript`,
  `--user-notes`, `--pid-file` — to unlock the live transcript panel
- **App icon** — replace the empty placeholder in Assets.xcassets
- **Homebrew cask** — `brew install --cask ownmeet` for one-command install
- **Signed + notarized DMG** — for distribution without Gatekeeper warnings

### Medium-term

- **Search within transcript** — cmd-F inside the transcript tab
- **Audio playback** — click a transcript line to seek to that moment
- **Slack integration** — post summary to a channel after each meeting
- **iCloud sync** — sync `~/ownscribe/` sessions across Macs
- **iPhone companion app** — record phone calls and in-person meetings
  (ownscribe already has an iOS model; needs a UI)

### Longer-term

- **OpenOats-style knowledge base** — point OwnMeet at a folder of notes;
  surface relevant context during live calls
- **CRM connectors** — push action items and summaries to HubSpot, Notion,
  Linear, or any Zapier-connected tool
- **Custom vocabulary** — inject domain-specific terms (product names, jargon)
  into the Whisper transcription prompt
- **Meeting analytics** — talk-time ratio, filler words, topic trends over time
- **Windows support** — ownscribe already supports Windows via sounddevice backend

---

## Distribution

OwnMeet **cannot** be distributed via the Mac App Store — subprocess spawning
requires disabling the App Sandbox, which App Store rules prohibit. Recommended
distribution paths:

- **Homebrew cask** — easiest for technical users
- **Direct DMG** — `bash scripts/build_app.sh --release` + Apple notarization
- **Build from source** — `bash scripts/build_app.sh --install` (30-second build)

---

## Contributing

Pull requests welcome. Areas of highest value:

1. Submit the ownscribe upstream patches (see `patches/ownscribe_patches.py`)
2. App icon design
3. Homebrew cask formula
4. Test coverage for SessionStore and OwnScribeProcessManager

---

## License

MIT — same license as [ownscribe](https://github.com/paberr/ownscribe) upstream.

---

*Built on top of [paberr/ownscribe](https://github.com/paberr/ownscribe) (MIT),
[WhisperX](https://github.com/m-bain/whisperX), and
[Phi-4-mini](https://huggingface.co/microsoft/Phi-4-mini-instruct).*
