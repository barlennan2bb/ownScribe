import Foundation
import Observation
import CoreFoundation

// MARK: – SessionStore

/// Reads and watches the ownscribe output directory (~/ownscribe/) for session folders.
@MainActor
@Observable
final class SessionStore {

    static let shared = SessionStore()

    var sessions: [Session] = []
    var isLoading = false

    private var dirWatcher: DirectoryWatcher?

    init() {
        Task { await reload() }
        startWatching()
    }

    // MARK: - Public

    func reload() async {
        isLoading = true
        let dir = ownscribeDirectory
        let loaded = await Task.detached(priority: .userInitiated) {
            SessionStore.loadSessionsNonisolated(from: dir)
        }.value
        sessions = loaded
        isLoading = false
    }

    /// Delete a session from disk
    func delete(_ session: Session) throws {
        try FileManager.default.removeItem(at: session.directoryURL)
        sessions.removeAll { $0.id == session.id }
    }

    /// Save edited user notes back to disk
    func saveUserNotes(_ text: String, for session: Session) throws {
        try text.write(to: session.userNotesURL, atomically: true, encoding: .utf8)
    }

    /// Save edited summary back to disk
    func saveSummary(_ text: String, for session: Session) throws {
        try text.write(to: session.summaryURL, atomically: true, encoding: .utf8)
        // Refresh title in the list
        if let idx = sessions.firstIndex(of: session) {
            var updated = sessions[idx]
            updated = Session(directoryURL: updated.directoryURL)
            sessions[idx] = updated
        }
    }

    // MARK: - Private

    private var ownscribeDirectory: URL {
        let raw = AppSettings.shared.outputDirectory
        let expanded = NSString(string: raw).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    // nonisolated so it can be called from Task.detached without Swift 6 actor errors
    nonisolated static func loadSessionsNonisolated(from dir: URL) -> [Session] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        // ownscribe dirs: YYYY-MM-DD_HHMM  OR  YYYY-MM-DD_HHMM_slug-title
        let datePattern = try? NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}_\d{4}"#)
        return entries
            .filter { url in
                guard let vals = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                      vals.isDirectory == true else { return false }
                let name = url.lastPathComponent
                return datePattern?.firstMatch(
                    in: name,
                    range: NSRange(name.startIndex..., in: name)
                ) != nil
            }
            .map { Session(directoryURL: $0) }
            .sorted { $0.date > $1.date }
    }

    private func startWatching() {
        let dir = ownscribeDirectory
        dirWatcher = DirectoryWatcher(url: dir) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.reload()
            }
        }
    }
}

// MARK: – DirectoryWatcher (GCD-based, no CoreServices import needed)

private final class DirectoryWatcher: @unchecked Sendable {
    private var source: DispatchSourceFileSystemObject?
    private let fd: Int32
    private let callback: @Sendable () -> Void

    init(url: URL, callback: @escaping @Sendable () -> Void) {
        self.callback = callback
        // Create ~/ownscribe if it doesn't exist yet
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        self.fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // If directory doesn't exist yet, we can't watch — that's fine
            source = nil
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .global(qos: .utility)
        )
        src.setEventHandler { [weak self] in self?.callback() }
        src.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 { close(fd) }
        }
        src.resume()
        self.source = src
    }

    deinit {
        source?.cancel()
    }
}
