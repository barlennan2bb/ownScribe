import SwiftUI
import AVFoundation

// MARK: – OnboardingView

/// First-launch sheet: walks the user through permissions, dependency check, and model warmup.
struct OnboardingView: View {

    @Environment(OwnScribeInstaller.self) private var installer
    @Environment(AppSettings.self) private var settings
    @Environment(CalendarManager.self) private var calendar
    @Environment(\.dismiss) private var dismiss

    @State private var step: OnboardingStep = .welcome
    @State private var micGranted = false
    @State private var screenGranted = false

    enum OnboardingStep: Int, CaseIterable {
        case welcome, permissions, dependencies, warmup, done
        var next: OnboardingStep? {
            OnboardingStep(rawValue: rawValue + 1)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                    Circle()
                        .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 24)

            Spacer()

            // Step content
            Group {
                switch step {
                case .welcome:      welcomeStep
                case .permissions:  permissionsStep
                case .dependencies: dependenciesStep
                case .warmup:       warmupStep
                case .done:         doneStep
                }
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: 480)

            Spacer()

            // Navigation buttons
            HStack {
                if step != .welcome {
                    Button("Back") {
                        withAnimation { step = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome }
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                nextButton
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(width: 560, height: 440)
        .onAppear {
            checkExistingPermissions()
            Task { await installer.check() }
        }
    }

    // MARK: – Steps

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 72))
                .foregroundStyle(.tint)

            Text("Welcome to OwnMeet")
                .font(.largeTitle.weight(.bold))

            Text("Local-first meeting notes powered by ownscribe. All recording, transcription, and AI summarization happens on your Mac. Nothing leaves your device.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Permissions")
                .font(.title.weight(.bold))

            permissionRow(
                title: "Microphone",
                detail: "To record your voice during meetings.",
                systemImage: "mic.fill",
                granted: micGranted
            ) {
                Task {
                    let status = await AVCaptureDevice.requestAccess(for: .audio)
                    micGranted = status
                }
            }

            permissionRow(
                title: "Screen Recording",
                detail: "Required to capture system audio (Zoom, Teams, Meet).",
                systemImage: "record.circle",
                granted: screenGranted
            ) {
                // Screen recording can only be granted via System Settings
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
                )
            }

            permissionRow(
                title: "Calendar (optional)",
                detail: "To show today's meetings and auto-start recording.",
                systemImage: "calendar",
                granted: calendar.hasCalendarAccess
            ) {
                Task { await calendar.requestAccess() }
            }
        }
    }

    private func permissionRow(title: String, detail: String, systemImage: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Grant") { action() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var dependenciesStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "cube.box")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Dependencies")
                .font(.title.weight(.bold))

            switch installer.state {
            case .checking:
                ProgressView("Checking for ownscribe…")
            case .ready(let v):
                VStack(spacing: 8) {
                    Label("ownscribe \(v) — ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("All dependencies are installed.")
                        .foregroundStyle(.secondary)
                }
            case .uvxMissing:
                VStack(spacing: 12) {
                    Label("uv not found", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("OwnMeet uses `uvx ownscribe` to run the transcription pipeline. Install `uv` to continue.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Install uv via Homebrew") {
                        Task { await installer.installUV() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .installing:
                ProgressView("Installing uv…")
                    .progressViewStyle(.linear)
            case .failed(let reason):
                VStack(spacing: 8) {
                    Label("Installation failed", systemImage: "xmark.circle")
                        .foregroundStyle(.red)
                    Text(reason).font(.callout).foregroundStyle(.secondary)
                    Text("You can install manually: `brew install uv`")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var warmupStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Download Models")
                .font(.title.weight(.bold))

            Text("OwnMeet uses WhisperX for transcription and Phi-4-mini for summarization. Downloading them now avoids delays when your first meeting starts.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                HStack {
                    Text("WhisperX (small)"); Spacer(); Text("~466 MB")
                }
                HStack {
                    Text("Phi-4-mini (LLM)"); Spacer(); Text("~2.4 GB")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding()
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            switch installer.state {
            case .installing:
                ProgressView("Downloading models… (this may take a few minutes)")
                    .progressViewStyle(.linear)
            case .ready:
                Label("Models ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            default:
                Button("Download now (recommended)") {
                    Task { await installer.warmup() }
                }
                .buttonStyle(.borderedProminent)

                Button("Skip — download on first recording") {
                    withAnimation { step = .done }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var doneStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)

            Text("You're all set!")
                .font(.largeTitle.weight(.bold))

            Text("Press ⌘⇧R any time to start recording. OwnMeet lives in your menu bar.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "waveform")
                Text("Look for the waveform icon in your menu bar.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: – Next button

    @ViewBuilder
    private var nextButton: some View {
        switch step {
        case .done:
            Button("Start using OwnMeet") {
                settings.hasCompletedOnboarding = true
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)

        case .dependencies:
            Button("Next") {
                guard installer.isReady else { return }
                withAnimation { step = step.next ?? .done }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!installer.isReady)

        default:
            Button("Next") {
                withAnimation { step = step.next ?? .done }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: – Helpers

    private func checkExistingPermissions() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        // Screen recording has no programmatic check — assume not granted initially
    }
}
