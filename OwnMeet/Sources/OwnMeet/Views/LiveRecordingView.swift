import SwiftUI

// MARK: – LiveRecordingView

/// Shown as the detail pane while ownscribe is recording.
/// Left: live transcript stream. Right: raw notes notepad.
struct LiveRecordingView: View {

    @Environment(OwnScribeProcessManager.self) private var pm

    @State private var userNotes = ""
    @State private var scrollProxy: ScrollViewProxy? = nil

    var body: some View {
        HSplitView {
            // Left — Live transcript
            transcriptPanel
                .frame(minWidth: 300)

            // Right — Raw notes
            notesPanel
                .frame(minWidth: 240, maxWidth: 360)
        }
        .toolbar { toolbarItems }
        .onChange(of: pm.transcriptLines.count) { _, _ in
            scrollToBottom()
        }
    }

    // MARK: – Transcript panel

    private var transcriptPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Live Transcript", systemImage: "waveform")
                    .font(.headline)
                Spacer()
                if pm.isRecording {
                    HStack(spacing: 6) {
                        Circle().fill(.red).frame(width: 8, height: 8)
                            .symbolEffect(.pulse)
                        Text(formatElapsed(pm.elapsedSeconds))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.red)
                    }
                } else {
                    Label("Summarizing…", systemImage: "ellipsis")
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)

            Divider()

            // Transcript scroll view
            if pm.transcriptLines.isEmpty {
                transcriptPlaceholder
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(pm.transcriptLines) { line in
                                transcriptLineView(line)
                                    .id(line.id)
                            }
                        }
                        .padding(16)
                    }
                    .onAppear { scrollProxy = proxy }
                }
            }
        }
    }

    private var transcriptPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
                .symbolEffect(.variableColor.iterative, isActive: pm.isRecording)
            Text(pm.isRecording ? "Listening…" : "Waiting for transcript…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func transcriptLineView(_ line: TranscriptLine) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let speaker = line.speaker, !speaker.isEmpty {
                HStack(spacing: 4) {
                    Text(line.formattedTimestamp)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Text(line.speakerDisplayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(speakerColor(line.speaker))
                }
            } else {
                Text(line.formattedTimestamp)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Text(line.text)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    // MARK: – Notes panel

    private var notesPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Your Notes", systemImage: "pencil")
                    .font(.headline)
                Spacer()
                Text("Markdown")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)

            Divider()

            TextEditor(text: $userNotes)
                .font(.callout)
                .padding(12)

            Divider()

            Text("Notes are passed to the AI to anchor your summary.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(8)
        }
        .onChange(of: pm.isIdle) { _, idle in
            if idle { saveNotes() }
        }
    }

    // MARK: – Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                pm.stopRecording()
            } label: {
                Label("Stop & Summarize", systemImage: "stop.circle.fill")
                    .foregroundStyle(.red)
            }
            .disabled(!pm.isRecording)
        }

        ToolbarItem {
            Button {
                pm.toggleMicMute()
            } label: {
                Label(pm.isMicMuted ? "Unmute Mic" : "Mute Mic",
                      systemImage: pm.isMicMuted ? "mic.slash.fill" : "mic.fill")
            }
            .disabled(!pm.isRecording)
        }
    }

    // MARK: – Helpers

    private func scrollToBottom() {
        guard let last = pm.transcriptLines.last else { return }
        withAnimation { scrollProxy?.scrollTo(last.id, anchor: .bottom) }
    }

    private func saveNotes() {
        guard let dir = pm.currentSessionDir, !userNotes.isEmpty else { return }
        let url = dir.appending(path: "user_notes.md")
        try? userNotes.write(to: url, atomically: true, encoding: .utf8)
    }

    private func formatElapsed(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func speakerColor(_ speaker: String?) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .cyan, .mint]
        guard let sp = speaker, sp.hasPrefix("SPEAKER_"),
              let n = Int(sp.dropFirst(8)) else { return .accentColor }
        return colors[n % colors.count]
    }
}
