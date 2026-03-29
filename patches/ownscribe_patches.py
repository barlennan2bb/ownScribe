"""
ownScribe GUI patches for OwnMeet
==================================
These patches add four new CLI flags to ownscribe to support OwnMeet's GUI layer.
They are designed to be submitted as upstream PRs to paberr/ownscribe.

To apply:
  1. Clone ownscribe: git clone https://github.com/paberr/ownscribe && cd ownscribe
  2. Apply each patch section below to the appropriate file.
  3. Build and install: uv sync --extra transcription && uv pip install -e .

Patch 1: --json-progress
------------------------
File: src/ownscribe/cli.py (or wherever the main Typer/Click app is)

Instead of using Rich's TUI output (which OwnMeet can't easily parse),
emit structured JSON lines to stdout when --json-progress is set.

Example JSON events:
  {"type": "session_dir", "path": "~/ownscribe/2026-03-29_143022"}
  {"type": "progress",    "message": "Transcribing…", "step": "transcribe"}
  {"type": "summarizing", "message": "Summarizing with phi-4-mini…"}
  {"type": "transcript_chunk", "text": "Hello everyone", "start": 1.23, "speaker": "SPEAKER_00"}
  {"type": "done", "session_dir": "~/ownscribe/2026-03-29_143022"}
  {"type": "error", "message": "WhisperX failed: …"}

Sample implementation (pseudo-code):
"""

import json
import sys
from pathlib import Path
from typing import Optional


def emit_json(type: str, **kwargs) -> None:
    """
    Emit a single JSON progress event to stdout.
    Called throughout the pipeline when --json-progress is active.
    """
    event = {"type": type, **kwargs}
    print(json.dumps(event), flush=True)


# ─── Patch 1: --json-progress flag ──────────────────────────────────────────
#
# Add to the main CLI entry point (e.g. in the `record` command):
#
# @app.command()
# def record(
#     ...existing args...,
#     json_progress: bool = typer.Option(False, "--json-progress",
#         help="Emit JSON progress events to stdout instead of TUI output"),
#     pid_file: Optional[Path] = typer.Option(None, "--pid-file",
#         help="Write process PID to this file"),
#     stream_transcript: bool = typer.Option(False, "--stream-transcript",
#         help="Stream transcript chunks as JSON events during recording"),
#     user_notes: Optional[Path] = typer.Option(None, "--user-notes",
#         help="Path to a Markdown file with user notes to inject into summarization"),
# ):
#     if pid_file:
#         pid_file.write_text(str(os.getpid()))
#
#     session_dir = make_session_dir()  # existing logic
#     if json_progress:
#         emit_json("session_dir", path=str(session_dir))
#
#     # ... existing recording setup ...
#
#     if json_progress:
#         emit_json("progress", message="Recording…", step="record")
#
#     # After recording stops (SIGINT):
#     if json_progress:
#         emit_json("progress", message="Transcribing…", step="transcribe")
#
#     # After transcription:
#     if json_progress:
#         emit_json("progress", message="Summarizing…", step="summarize")
#         emit_json("summarizing")
#
#     # After summarization:
#     if json_progress:
#         emit_json("done", session_dir=str(session_dir))


# ─── Patch 2: --stream-transcript ────────────────────────────────────────────
#
# In the transcription module (e.g. src/ownscribe/transcribe.py):
#
# WhisperX processes audio in segments. After each segment is transcribed,
# emit it as a JSON line if streaming is enabled.
#
# def transcribe_segments(audio_path, ..., stream: bool = False):
#     result = whisperx.transcribe(audio_path, ...)
#     for segment in result["segments"]:
#         if stream:
#             emit_json(
#                 "transcript_chunk",
#                 text=segment["text"].strip(),
#                 start=segment["start"],
#                 end=segment["end"],
#                 speaker=segment.get("speaker"),
#             )
#         yield segment


# ─── Patch 3: --user-notes ───────────────────────────────────────────────────
#
# In the summarization module (e.g. src/ownscribe/summarize.py):
#
# def build_prompt(transcript: str, template: str, user_notes: str = "") -> str:
#     base = TEMPLATES[template]["prompt"]
#     if user_notes:
#         # Inject user notes before the transcript so the LLM prioritizes them
#         notes_section = f"\n\n## User Notes (high priority):\n{user_notes}\n\n"
#         base = base.replace("{transcript}", notes_section + "{transcript}")
#     return base.format(transcript=transcript)
#
# Then in the CLI:
# if user_notes and user_notes.exists():
#     notes_text = user_notes.read_text()
#     prompt = build_prompt(transcript_text, template, user_notes=notes_text)
# else:
#     prompt = build_prompt(transcript_text, template)


# ─── Patch 4: --pid-file ─────────────────────────────────────────────────────
#
# At the start of the record command, before audio capture begins:
#
# import os
# if pid_file:
#     Path(pid_file).write_text(str(os.getpid()))
#
# This lets OwnMeet send SIGINT reliably without relying on proc.interrupt()
# which may not reach the correct process when run through uvx.


# ─── Mic mute via SIGUSR1 ────────────────────────────────────────────────────
#
# In the audio capture loop:
# import signal
# mic_muted = False
#
# def handle_sigusr1(signum, frame):
#     global mic_muted
#     mic_muted = not mic_muted
#     print(f"Mic {'muted' if mic_muted else 'unmuted'}", file=sys.stderr)
#
# signal.signal(signal.SIGUSR1, handle_sigusr1)
#
# In the audio capture loop:
# if mic_muted:
#     chunk = np.zeros_like(chunk)  # zero out mic audio


if __name__ == "__main__":
    # Demo: show what the JSON events look like
    emit_json("session_dir", path="~/ownscribe/2026-03-29_143022")
    emit_json("progress", message="Recording…", step="record")
    emit_json("transcript_chunk", text="Hello everyone.", start=1.23, speaker="SPEAKER_00")
    emit_json("transcript_chunk", text="Thanks for joining.", start=3.45, speaker="SPEAKER_01")
    emit_json("summarizing")
    emit_json("done", session_dir="~/ownscribe/2026-03-29_143022")
