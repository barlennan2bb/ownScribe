import Foundation
import Observation

// MARK: – OwnScribeInstaller

/// Checks whether ownscribe (via uvx) is available and installs it if not.
@MainActor
@Observable
final class OwnScribeInstaller {

    static let shared = OwnScribeInstaller()

    enum InstallState: Equatable {
        case checking
        case ready(version: String)
        case uvxMissing
        case installing
        case failed(reason: String)
    }

    var state: InstallState = .checking

    // MARK: – Public

    func check() async {
        state = .checking
        if let version = await detectOwnScribeVersion() {
            state = .ready(version: version)
        } else if isUVXAvailable() {
            // uvx is there but ownscribe hasn't been cached yet — first run will fetch it
            state = .ready(version: "latest (will fetch on first run)")
        } else {
            state = .uvxMissing
        }
    }

    /// Install `uv` via Homebrew (also gives us `uvx`)
    func installUV() async {
        guard isBrewAvailable() else {
            state = .failed(reason: "Homebrew not found. Install Homebrew first: brew.sh")
            return
        }
        state = .installing
        do {
            try await runShell("/opt/homebrew/bin/brew", args: ["install", "uv"])
            await check()
        } catch {
            state = .failed(reason: "brew install uv failed: \(error.localizedDescription)")
        }
    }

    /// Pre-warm ownscribe models (downloads Whisper + Phi-4-mini)
    func warmup() async {
        state = .installing
        do {
            try await runShell(uvxPath ?? "/opt/homebrew/bin/uvx", args: ["ownscribe", "warmup"])
            await check()
        } catch {
            state = .failed(reason: "warmup failed: \(error.localizedDescription)")
        }
    }

    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    var needsUVX: Bool { state == .uvxMissing }

    // MARK: – Private

    private var uvxPath: String? {
        let candidates = ["/opt/homebrew/bin/uvx", "/usr/local/bin/uvx",
                          "\(NSHomeDirectory())/.local/bin/uvx"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func isUVXAvailable() -> Bool { uvxPath != nil }

    private func isBrewAvailable() -> Bool {
        FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/brew") ||
        FileManager.default.isExecutableFile(atPath: "/usr/local/bin/brew")
    }

    private func detectOwnScribeVersion() async -> String? {
        guard let uvx = uvxPath else { return nil }
        do {
            let output = try await runShellOutput(uvx, args: ["ownscribe", "--version"])
            let v = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty ? nil : v
        } catch {
            return nil
        }
    }

    @discardableResult
    private func runShell(_ exe: String, args: [String]) async throws -> Int32 {
        try await withCheckedThrowingContinuation { cont in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: exe)
            proc.arguments = args
            proc.terminationHandler = { p in cont.resume(returning: p.terminationStatus) }
            do { try proc.run() } catch { cont.resume(throwing: error) }
        }
    }

    private func runShellOutput(_ exe: String, args: [String]) async throws -> String {
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: exe)
        proc.arguments = args
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try proc.run()
        var out = ""
        for try await line in pipe.fileHandleForReading.bytes.lines { out += line + "\n" }
        proc.waitUntilExit()
        return out
    }
}
