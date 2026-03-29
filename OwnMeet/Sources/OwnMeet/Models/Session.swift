import Foundation

// MARK: – Session

/// Represents one ownscribe recording session stored in ~/ownscribe/YYYY-MM-DD_HHMMSS/
struct Session: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var date: Date
    let directoryURL: URL
    var template: String
    var calendarEventTitle: String?
    var durationSeconds: Double?

    // Derived file URLs
    var summaryURL: URL    { directoryURL.appending(path: "summary.md") }
    var transcriptURL: URL { directoryURL.appending(path: "transcript.md") }
    var audioURL: URL      { directoryURL.appending(path: "recording.wav") }
    var userNotesURL: URL  { directoryURL.appending(path: "user_notes.md") }
    var metaURL: URL       { directoryURL.appending(path: "ownmeet.json") }

    var hasSummary: Bool    { FileManager.default.fileExists(atPath: summaryURL.path) }
    var hasTranscript: Bool { FileManager.default.fileExists(atPath: transcriptURL.path) }
    var hasAudio: Bool      { FileManager.default.fileExists(atPath: audioURL.path) }

    // MARK: Init from directory

    init(directoryURL: URL) {
        self.id = UUID()
        self.directoryURL = directoryURL
        self.template = "meeting"

        // Parse date from directory name: YYYY-MM-DD_HHMMSS
        let name = directoryURL.lastPathComponent
        // Extract just the YYYY-MM-DD_HHMM prefix (15 chars) before any slug suffix
        let datePart = name.count >= 15 ? String(name.prefix(15)) : name
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd_HHmm"
        self.date = fmt.date(from: datePart) ?? Date()

        // Try to load ownmeet.json for extra metadata
        if let data = try? Data(contentsOf: directoryURL.appending(path: "ownmeet.json")),
           let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            self.calendarEventTitle = meta["calendarEventTitle"] as? String
            self.template = meta["template"] as? String ?? "meeting"
            self.durationSeconds = meta["durationSeconds"] as? Double
        }

        // Default title from date (ensures self.title is always initialized before use)
        self.title = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)

        // Try to derive a better title: summary headline > calendar event > date string
        if let summaryRaw = try? String(contentsOf: summaryURL, encoding: .utf8),
           let headline = summaryRaw.components(separatedBy: "\n").first(where: { $0.hasPrefix("# ") }) {
            self.title = String(headline.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        } else if let event = calendarEventTitle {
            self.title = event
        }
    }

    // MARK: Hashable / Equatable
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Session, rhs: Session) -> Bool { lhs.id == rhs.id }

    // MARK: Helpers

    var formattedDuration: String? {
        guard let secs = durationSeconds else { return nil }
        let m = Int(secs) / 60
        let s = Int(secs) % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    /// Read raw transcript text from disk
    func transcriptText() -> String {
        (try? String(contentsOf: transcriptURL, encoding: .utf8)) ?? ""
    }

    /// Read summary text from disk
    func summaryText() -> String {
        (try? String(contentsOf: summaryURL, encoding: .utf8)) ?? ""
    }

    /// Read user notes text from disk
    func userNotesText() -> String {
        (try? String(contentsOf: userNotesURL, encoding: .utf8)) ?? ""
    }

    /// Persist ownmeet metadata alongside ownscribe output
    func saveMetadata() {
        var meta: [String: Any] = [
            "template": template,
            "savedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        if let event = calendarEventTitle { meta["calendarEventTitle"] = event }
        if let dur = durationSeconds { meta["durationSeconds"] = dur }
        if let data = try? JSONSerialization.data(withJSONObject: meta, options: .prettyPrinted) {
            try? data.write(to: metaURL)
        }
    }
}
