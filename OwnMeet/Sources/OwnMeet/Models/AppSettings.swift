import Foundation
import Observation

// MARK: – AppSettings

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()
    private let ud = UserDefaults.standard

    // MARK: - Whisper

    var whisperModel: WhisperModel {
        get { WhisperModel(rawValue: ud.string(forKey: "whisperModel") ?? "") ?? .small }
        set { ud.set(newValue.rawValue, forKey: "whisperModel") }
    }

    var transcriptionLanguage: String {
        get { ud.string(forKey: "transcriptionLanguage") ?? "" }
        set { ud.set(newValue, forKey: "transcriptionLanguage") }
    }

    // MARK: - Audio

    var captureSystemAudio: Bool {
        get { ud.object(forKey: "captureSystemAudio") as? Bool ?? true }
        set { ud.set(newValue, forKey: "captureSystemAudio") }
    }

    var captureMicrophone: Bool {
        get { ud.bool(forKey: "captureMicrophone") }
        set { ud.set(newValue, forKey: "captureMicrophone") }
    }

    var micDevice: String {
        get { ud.string(forKey: "micDevice") ?? "" }
        set { ud.set(newValue, forKey: "micDevice") }
    }

    var silenceTimeoutSeconds: Int {
        get { let v = ud.integer(forKey: "silenceTimeoutSeconds"); return v == 0 ? 300 : v }
        set { ud.set(newValue, forKey: "silenceTimeoutSeconds") }
    }

    // MARK: - Diarization

    var enableDiarization: Bool {
        get { ud.bool(forKey: "enableDiarization") }
        set { ud.set(newValue, forKey: "enableDiarization") }
    }

    var huggingFaceToken: String {
        get { ud.string(forKey: "huggingFaceToken") ?? "" }
        set { ud.set(newValue, forKey: "huggingFaceToken") }
    }

    // MARK: - Summarization

    var defaultTemplate: MeetingTemplate {
        get { MeetingTemplate(rawValue: ud.string(forKey: "defaultTemplate") ?? "") ?? .meeting }
        set { ud.set(newValue.rawValue, forKey: "defaultTemplate") }
    }

    var llmBackend: LLMBackend {
        get { LLMBackend(rawValue: ud.string(forKey: "llmBackend") ?? "") ?? .local }
        set { ud.set(newValue.rawValue, forKey: "llmBackend") }
    }

    var llmHost: String {
        get { ud.string(forKey: "llmHost") ?? "http://localhost:11434" }
        set { ud.set(newValue, forKey: "llmHost") }
    }

    var llmModel: String {
        get { ud.string(forKey: "llmModel") ?? "phi-4-mini" }
        set { ud.set(newValue, forKey: "llmModel") }
    }

    // MARK: - Output

    var outputDirectory: String {
        get { ud.string(forKey: "outputDirectory") ?? "~/ownscribe" }
        set { ud.set(newValue, forKey: "outputDirectory") }
    }

    var keepRecordings: Bool {
        get { ud.object(forKey: "keepRecordings") as? Bool ?? true }
        set { ud.set(newValue, forKey: "keepRecordings") }
    }

    // MARK: - App State

    var hasCompletedOnboarding: Bool {
        get { ud.bool(forKey: "hasCompletedOnboarding") }
        set { ud.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    var autoStartWithCalendar: Bool {
        get { ud.bool(forKey: "autoStartWithCalendar") }
        set { ud.set(newValue, forKey: "autoStartWithCalendar") }
    }

    // MARK: - Enums

    enum WhisperModel: String, CaseIterable {
        case tiny, base, small, medium, large
        var displayName: String { rawValue.capitalized }
        var diskSize: String {
            switch self {
            case .tiny:   return "~75 MB"
            case .base:   return "~145 MB"
            case .small:  return "~466 MB"
            case .medium: return "~1.5 GB"
            case .large:  return "~3 GB"
            }
        }
        /// Name understood by ownscribe CLI
        var ownScribeName: String {
            self == .large ? "large-v3" : rawValue
        }
    }

    enum LLMBackend: String, CaseIterable {
        case local, ollama, openai
        var displayName: String {
            switch self {
            case .local:  return "Local (Phi-4-mini, built-in)"
            case .ollama: return "Ollama"
            case .openai: return "OpenAI-compatible"
            }
        }
        var requiresHost: Bool { self != .local }
    }

    enum MeetingTemplate: String, CaseIterable {
        case meeting, lecture, brief
        var displayName: String { rawValue.capitalized }
        var description: String {
            switch self {
            case .meeting:  return "Summary, Key Points, Action Items, Decisions"
            case .lecture:  return "Summary, Key Concepts, Key Takeaways"
            case .brief:    return "3–5 bullet overview"
            }
        }
    }
}
