import SwiftUI

// MARK: – OwnMeetApp

@main
struct OwnMeetApp: App {

    private let processManager      = OwnScribeProcessManager.shared
    private let sessionStore         = SessionStore.shared
    private let calendarMgr          = CalendarManager.shared
    private let installer            = OwnScribeInstaller.shared
    private let settings             = AppSettings.shared
    private let notificationManager  = NotificationManager.shared

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {

        // MARK: Menu bar extra (always visible)
        MenuBarExtra {
            MenuBarView()
                .environment(processManager)
                .environment(sessionStore)
                .environment(installer)
                .environment(settings)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.menu)

        // Request notification permission on first launch (needed for meeting alerts)
        // Using a background task so it doesn't block the app launch
        let _ = Task {
            await notificationManager.requestAuthorization()
        }

        // MARK: Main library window
        WindowGroup("OwnMeet", id: "library") {
            LibraryView()
                .environment(processManager)
                .environment(sessionStore)
                .environment(calendarMgr)
                .environment(installer)
                .environment(settings)
                .frame(minWidth: 820, minHeight: 520)
        }
        .defaultSize(width: 1060, height: 680)
        .commands {
            recordingCommands
        }

        // MARK: Settings window (Cmd+,)
        Settings {
            SettingsView()
                .environment(processManager)
                .environment(installer)
                .environment(settings)
        }
    }

    // MARK: – Menu bar icon

    @ViewBuilder
    private var menuBarLabel: some View {
        if processManager.isRecording {
            Label("Recording", systemImage: "waveform.circle.fill")
                .symbolRenderingMode(.multicolor)
        } else if processManager.isSummarizing {
            Label("Summarizing", systemImage: "ellipsis.circle.fill")
        } else {
            Label("OwnMeet", systemImage: "waveform")
        }
    }

    // MARK: – Keyboard shortcuts

    private var recordingCommands: some Commands {
        CommandMenu("Recording") {
            Button(processManager.isRecording ? "Stop Recording" : "Start Recording") {
                Task { @MainActor in
                    if processManager.isRecording {
                        processManager.stopRecording()
                    } else {
                        await processManager.startRecording()
                    }
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!processManager.isIdle && !processManager.isRecording)

            if processManager.isRecording {
                Divider()
                Button(processManager.isMicMuted ? "Unmute Mic" : "Mute Mic") {
                    processManager.toggleMicMute()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }
    }
}
