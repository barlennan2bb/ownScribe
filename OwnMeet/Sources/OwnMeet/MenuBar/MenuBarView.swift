import SwiftUI

// MARK: – MenuBarView

/// Content displayed when the user clicks the OwnMeet menu bar icon.
struct MenuBarView: View {

    @Environment(OwnScribeProcessManager.self) private var pm
    @Environment(SessionStore.self) private var store
    @Environment(OwnScribeInstaller.self) private var installer
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            // Status header
            statusSection

            Divider()

            // Recording controls
            recordingSection

            Divider()

            // Recent sessions
            if !store.sessions.isEmpty {
                recentSection
                Divider()
            }

            // App controls
            Button("Open OwnMeet…") { openWindow(id: "library") }
                .keyboardShortcut("o", modifiers: .command)

            SettingsLink { Text("Settings…") }
                .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit OwnMeet") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
    }

    // MARK: – Sections

    @ViewBuilder
    private var statusSection: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(pm.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            if pm.isRecording {
                Text(formatElapsed(pm.elapsedSeconds))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var recordingSection: some View {
        if pm.isRecording {
            Button {
                pm.stopRecording()
            } label: {
                Label("Stop Recording", systemImage: "stop.circle.fill")
                    .foregroundStyle(.red)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button(pm.isMicMuted ? "Unmute Mic" : "Mute Mic") {
                pm.toggleMicMute()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

        } else if pm.isSummarizing {
            Label("Summarizing…", systemImage: "ellipsis")
                .foregroundStyle(.secondary)

        } else {
            Button {
                Task { await pm.startRecording() }
            } label: {
                Label("Start Recording", systemImage: "waveform.circle.fill")
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!installer.isReady)
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        Text("Recent")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)

        ForEach(store.sessions.prefix(5)) { session in
            Button {
                openWindow(id: "library")
                // TODO: select session in library
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title)
                        .lineLimit(1)
                    Text(session.date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: – Helpers

    private var statusColor: Color {
        if pm.isRecording   { return .red }
        if pm.isSummarizing { return .orange }
        if pm.lastError != nil { return .red }
        return .green
    }

    private func formatElapsed(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
