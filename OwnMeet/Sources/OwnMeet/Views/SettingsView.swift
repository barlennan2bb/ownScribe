import SwiftUI

// MARK: – SettingsView

/// Tabbed settings panel (Cmd+,).
struct SettingsView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(OwnScribeInstaller.self) private var installer
    @Environment(OwnScribeProcessManager.self) private var pm

    @State private var selectedTab = SettingsTab.audio

    enum SettingsTab: String, CaseIterable {
        case audio       = "Audio"
        case transcription = "Transcription"
        case summarization = "Summarization"
        case calendar    = "Calendar & Auto-start"
        case about       = "About"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            audioTab.tabItem { Label("Audio", systemImage: "waveform") }.tag(SettingsTab.audio)
            transcriptionTab.tabItem { Label("Transcription", systemImage: "text.bubble") }.tag(SettingsTab.transcription)
            summarizationTab.tabItem { Label("Summarization", systemImage: "sparkles") }.tag(SettingsTab.summarization)
            calendarTab.tabItem { Label("Calendar", systemImage: "calendar") }.tag(SettingsTab.calendar)
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }.tag(SettingsTab.about)
        }
        .frame(width: 480)
        .padding(20)
    }

    // MARK: – Audio tab

    @ViewBuilder
    private var audioTab: some View {
        @Bindable var s = settings
        Form {
            Section("Input") {
                Toggle("Capture system audio (meetings, calls)", isOn: $s.captureSystemAudio)
                Toggle("Also capture microphone", isOn: $s.captureMicrophone)
                    .disabled(!settings.captureSystemAudio)
                HStack {
                    Text("Microphone device")
                    Spacer()
                    TextField("Default", text: $s.micDevice).frame(width: 200)
                }
            }
            Section("Auto-stop") {
                HStack {
                    Text("Silence timeout")
                    Spacer()
                    Stepper("\(settings.silenceTimeoutSeconds / 60) min",
                            value: $s.silenceTimeoutSeconds, in: 0...3600, step: 60)
                        .frame(width: 120)
                }
                Text("Set to 0 to disable auto-stop.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Recordings") {
                Toggle("Keep WAV recordings after transcription", isOn: $s.keepRecordings)
                HStack {
                    Text("Output directory")
                    Spacer()
                    TextField("~/ownscribe", text: $s.outputDirectory).frame(width: 200)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: – Transcription tab

    @ViewBuilder
    private var transcriptionTab: some View {
        @Bindable var s = settings
        Form {
            Section("Whisper Model") {
                Picker("Model", selection: $s.whisperModel) {
                    ForEach(AppSettings.WhisperModel.allCases, id: \.self) { m in
                        HStack {
                            Text(m.displayName)
                            Spacer()
                            Text(m.diskSize).foregroundStyle(.secondary)
                        }.tag(m)
                    }
                }
                Text("Larger models are more accurate but slower and use more disk space.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Language")
                    Spacer()
                    TextField("Auto-detect", text: $s.transcriptionLanguage)
                        .frame(width: 120)
                }
                Text("Enter an ISO 639-1 code (e.g. 'en', 'fr') or leave blank for auto-detection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Speaker Diarization") {
                Toggle("Identify speakers", isOn: $s.enableDiarization)
                if settings.enableDiarization {
                    HStack {
                        Text("HuggingFace token")
                        Spacer()
                        SecureField("hf_...", text: $s.huggingFaceToken)
                            .frame(width: 200)
                    }
                    Link("Get a token at huggingface.co",
                         destination: URL(string: "https://huggingface.co/settings/tokens")!)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: – Summarization tab

    @ViewBuilder
    private var summarizationTab: some View {
        @Bindable var s = settings
        Form {
            Section("Default Template") {
                Picker("Template", selection: $s.defaultTemplate) {
                    ForEach(AppSettings.MeetingTemplate.allCases, id: \.self) { t in
                        VStack(alignment: .leading) {
                            Text(t.displayName)
                            Text(t.description).font(.caption).foregroundStyle(.secondary)
                        }.tag(t)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section("LLM Backend") {
                Picker("Backend", selection: $s.llmBackend) {
                    ForEach(AppSettings.LLMBackend.allCases, id: \.self) { b in
                        Text(b.displayName).tag(b)
                    }
                }
                .pickerStyle(.radioGroup)

                if settings.llmBackend.requiresHost {
                    HStack {
                        Text("Host URL")
                        Spacer()
                        TextField("http://localhost:11434", text: $s.llmHost)
                            .frame(width: 220)
                    }
                    HStack {
                        Text("Model name")
                        Spacer()
                        TextField("phi-4-mini", text: $s.llmModel)
                            .frame(width: 160)
                    }
                }
            }

            Section {
                Button("Pre-download models (warmup)") {
                    Task { await installer.warmup() }
                }
                .disabled(!installer.isReady)

                Text("Warmup downloads Whisper and the LLM so the first recording starts instantly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: – Calendar & Auto-start tab

    @ViewBuilder
    private var calendarTab: some View {
        @Bindable var s = settings
        Form {
            Section("Calendar Integration") {
                Toggle("Show today's events in the sidebar", isOn: .constant(true))
                    .disabled(true)
                Toggle("Auto-prompt recording when a meeting starts", isOn: $s.autoStartWithCalendar)

                Button("Grant Calendar Access…") {
                    Task { await CalendarManager.shared.requestAccess() }
                }

                let status = CalendarManager.shared.authorizationStatus
                Label(
                    status == .fullAccess ? "Calendar access granted ✓" : "Calendar access not granted",
                    systemImage: status == .fullAccess ? "checkmark.circle.fill" : "xmark.circle"
                )
                .foregroundStyle(status == .fullAccess ? .green : .secondary)
                .font(.callout)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: – About tab

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            VStack(spacing: 4) {
                Text("OwnMeet")
                    .font(.title.weight(.bold))
                Text("Version 1.0.0")
                    .foregroundStyle(.secondary)
            }

            Text("Local-first meeting notes. No bots, no cloud, no subscription.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Divider()

            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("Powered by")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Link("ownscribe", destination: URL(string: "https://github.com/paberr/ownscribe")!)
                }
                VStack(spacing: 4) {
                    Text("Transcription")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("WhisperX")
                }
                VStack(spacing: 4) {
                    Text("Summarization")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("Phi-4-mini / Ollama")
                }
            }

            switch installer.state {
            case .ready(let v):
                Label("ownscribe \(v)", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            case .uvxMissing:
                Label("uvx not found", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            default:
                EmptyView()
            }

            Link("View source on GitHub",
                 destination: URL(string: "https://github.com/paberr/ownscribe")!)
                .font(.callout)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
