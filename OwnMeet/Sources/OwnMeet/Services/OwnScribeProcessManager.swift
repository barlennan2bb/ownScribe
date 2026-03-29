import Foundation
import Observation

// MARK: – OwnScribeProcessManager

/// Manages the lifecycle of the `ownscribe` CLI subprocess.
/// Reads stdout line-by-line to parse progress events and streaming transcript chunks.
@MainActor
@Observable
final class OwnScribeProcessManager {

    static let shared = OwnScribeProcessManager()

    // MARK: Published state

    var isRecording       = false
    var isSummarizing     = false
    var isIdle            = true
    var statusMessage     = "Ready"
    var elapsedSeconds    = 0.0
    var transcriptLines: [TranscriptLine] = []
    var currentSessionDir: URL?
    var lastError: String?
    var isMicMuted        = false

    // MARK: Private

    private var process: Process?
    private var outputPipe: Pipe?
    private var elapsedTimer: Timer?
    private var recordingStart: Date?

    // MARK: – Start recording

    func startRecording(calendarEventTitle: String? = nil) async {
        guard isIdle else { return }
        let settings = AppSettings.shared
        lastError = nil
        transcriptLines = []
        currentSessionDir = nil

        // Build ownscribe command arguments
        var args: [String] = []

        // System audio or device
        if settings.captureSystemAudio && !settings.captureMicrophone {
            // default — system audio only
        } else if settings.captureSystemAudio && settings.captureMicrophone {
            args += ["--mic"]
            if !settings.micDevice.isEmpty {
                args += ["--mic-device", settings.micDevice]
            }
        } else {
            // mic only
            if settings.micDevice.isEmpty {
                args += ["--device", settings.micDevice]
            }
        }

        args += ["--template", settings.defaultTemplate.rawValue]
        args += ["--model",    settings.whisperModel.ownScribeName]
        args += ["--silence-timeout", "\(settings.silenceTimeoutSeconds)"]

        if !settings.transcriptionLanguage.isEmpty {
            args += ["--language", settings.transcriptionLanguage]
        }
        if settings.enableDiarization {
            args += ["--diarize"]
        }
        if !settings.keepRecordings {
            args += ["--no-keep-recording"]
        }

        // Backend
        switch settings.llmBackend {
        case .local:
            break
        case .ollama:
            // ownscribe reads OLLAMA_HOST from env; pass model via args once patch lands
            break
        case .openai:
            break
        }

        // Patches: stream transcript + JSON progress (falls back gracefully if not patched)
        args += ["--stream-transcript", "--json-progress"]

        // PID file so we can reliably signal
        let pidFile = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "ownmeet.pid")
        args += ["--pid-file", pidFile.path]

        await spawnProcess(args: args, calendarEventTitle: calendarEventTitle)
    }

    // MARK: – Stop recording

    func stopRecording() {
        guard isRecording else { return }
        // Send SIGINT (Ctrl+C) — ownscribe finishes the pipeline gracefully
        if let proc = process, proc.isRunning {
            proc.interrupt()
        }
        isRecording = false
        isSummarizing = true
        statusMessage = "Transcribing & summarizing…"
        stopElapsedTimer()
    }

    // MARK: – Toggle mic mute (POSIX signal SIGUSR1 — requires ownscribe patch)

    func toggleMicMute() {
        guard isRecording, let proc = process, proc.isRunning else { return }
        kill(proc.processIdentifier, SIGUSR1)
        isMicMuted.toggle()
    }

    // MARK: – Run ownscribe ask

    func ask(question: String, since: Date? = nil, limit: Int = 5) async throws -> String {
        var args = [question]
        if let s = since {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            args += ["--since", df.string(from: s)]
        }
        args += ["--limit", "\(limit)"]
        return try await runSubcommand("ask", args: args)
    }

    // MARK: – Run ownscribe warmup

    func warmup() async throws {
        _ = try await runSubcommand("warmup", args: [])
    }

    // MARK: – Run ownscribe summarize (re-summarize existing session)

    func resummarize(session: Session, template: String) async throws {
        _ = try await runSubcommand(
            "summarize",
            args: [session.transcriptURL.path, "--template", template]
        )
    }

    // MARK: - Private helpers

    private func spawnProcess(args: [String], calendarEventTitle: String?) async {
        let proc = Process()
        let pipe = Pipe()
        let errPipe = Pipe()

        // Resolve uvx path
        guard let uvxPath = resolveUVX() else {
            lastError = "uvx not found. Please run scripts/install_ownscribe.sh"
            return
        }

        proc.executableURL = URL(fileURLWithPath: uvxPath)
        proc.arguments = ["ownscribe"] + args
        proc.standardOutput = pipe
        proc.standardError = errPipe

        // Pass through environment, adding HF_TOKEN if set
        var env = ProcessInfo.processInfo.environment
        let hfToken = AppSettings.shared.huggingFaceToken
        if !hfToken.isEmpty { env["HF_TOKEN"] = hfToken }
        if AppSettings.shared.llmBackend == .ollama {
            env["OLLAMA_HOST"] = AppSettings.shared.llmHost
        }
        proc.environment = env

        proc.terminationHandler = { [weak self] p in
            Task { @MainActor [weak self] in
                self?.handleTermination(exitCode: p.terminationStatus)
            }
        }

        do {
            try proc.run()
        } catch {
            lastError = "Failed to launch ownscribe: \(error.localizedDescription)"
            return
        }

        self.process = proc
        self.outputPipe = pipe
        self.isRecording = true
        self.isIdle = false
        self.statusMessage = "Recording…"
        self.recordingStart = Date()
        startElapsedTimer()

        // Stream stdout line by line
        let handle = pipe.fileHandleForReading
        Task.detached { [weak self] in
            do {
                for try await line in handle.bytes.lines {
                    guard !line.isEmpty else { continue }
                    await self?.processOutputLine(line)
                }
            } catch {
                // pipe closed — normal when process ends
            }
        }
    }

    private func processOutputLine(_ line: String) {
        // Try JSON first (patched ownscribe)
        if line.hasPrefix("{"),
           let data = line.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = json["type"] as? String {
            handleJSONEvent(type: type, json: json)
            return
        }

        // Fallback: scan plain-text output for key markers
        if line.contains("Saving to") || line.contains("~/ownscribe/") {
            // extract session directory
            if let range = line.range(of: "~/ownscribe/") {
                let tail = String(line[range.lowerBound...]).components(separatedBy: " ").first ?? ""
                let expanded = NSString(string: tail).expandingTildeInPath
                currentSessionDir = URL(fileURLWithPath: expanded)
            }
        } else if line.lowercased().contains("summariz") {
            isSummarizing = true
            isRecording = false
            statusMessage = "Summarizing…"
        } else if line.lowercased().contains("done") || line.lowercased().contains("complete") {
            statusMessage = "Done"
        }
    }

    private func handleJSONEvent(type: String, json: [String: Any]) {
        switch type {
        case "transcript_chunk":
            if let line = TranscriptLine.fromJSON(String(data: (try? JSONSerialization.data(withJSONObject: json)) ?? Data(), encoding: .utf8) ?? "") {
                transcriptLines.append(line)
            }
        case "session_dir":
            if let path = json["path"] as? String {
                currentSessionDir = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
            }
        case "progress":
            if let msg = json["message"] as? String { statusMessage = msg }
        case "summarizing":
            isRecording = false
            isSummarizing = true
            statusMessage = "Summarizing…"
        case "done":
            isSummarizing = false
            isIdle = true
            statusMessage = "Done ✓"
            reloadSessionStore()
        case "error":
            lastError = json["message"] as? String ?? "Unknown error"
        default:
            break
        }
    }

    private func handleTermination(exitCode: Int32) {
        stopElapsedTimer()
        if exitCode == 0 {
            isSummarizing = false
            isIdle = true
            statusMessage = "Done ✓"
            reloadSessionStore()
        } else if exitCode == 2 || exitCode == SIGINT {
            // Interrupted by user — pipeline continues in ownscribe
            // Nothing to do, we already sent SIGINT intentionally
        } else {
            isRecording = false
            isSummarizing = false
            isIdle = true
            if lastError == nil { lastError = "ownscribe exited with code \(exitCode)" }
            statusMessage = "Error"
        }
        process = nil
    }

    private func reloadSessionStore() {
        Task { @MainActor in
            await SessionStore.shared.reload()
        }
    }

    // MARK: - Elapsed timer

    private func startElapsedTimer() {
        elapsedSeconds = 0
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.recordingStart else { return }
                self.elapsedSeconds = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    // MARK: - uvx resolution

    private func resolveUVX() -> String? {
        let candidates = [
            "/opt/homebrew/bin/uvx",
            "/usr/local/bin/uvx",
            "\(NSHomeDirectory())/.local/bin/uvx",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Generic subcommand runner

    private func runSubcommand(_ subcommand: String, args: [String]) async throws -> String {
        guard let uvxPath = resolveUVX() else {
            throw OwnScribeError.uvxNotFound
        }
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: uvxPath)
        proc.arguments = ["ownscribe", subcommand] + args
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try proc.run()

        var output = ""
        for try await line in pipe.fileHandleForReading.bytes.lines {
            output += line + "\n"
        }
        proc.waitUntilExit()
        return output
    }
}

// MARK: – Errors

enum OwnScribeError: LocalizedError {
    case uvxNotFound
    case processLaunchFailed(String)

    var errorDescription: String? {
        switch self {
        case .uvxNotFound:
            return "uvx not found. Install it with: brew install uv"
        case .processLaunchFailed(let msg):
            return "Failed to launch ownscribe: \(msg)"
        }
    }
}
