import Foundation

// MARK: – TranscriptLine

/// One chunk of speech emitted by ownscribe (live streaming or parsed from transcript.md)
struct TranscriptLine: Identifiable, Sendable, Hashable {
    let id: UUID
    let text: String
    let timestamp: TimeInterval   // seconds from start of recording
    let speaker: String?          // e.g. "SPEAKER_00", nil if diarization disabled

    init(text: String, timestamp: TimeInterval, speaker: String? = nil) {
        self.id = UUID()
        self.text = text
        self.timestamp = timestamp
        self.speaker = speaker
    }

    // MARK: Formatting

    var formattedTimestamp: String {
        let h = Int(timestamp) / 3600
        let m = (Int(timestamp) % 3600) / 60
        let s = Int(timestamp) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// Display-friendly speaker name (maps SPEAKER_00 → "Speaker 1", etc.)
    var speakerDisplayName: String {
        guard let sp = speaker else { return "" }
        if sp.hasPrefix("SPEAKER_"), let n = Int(sp.dropFirst(8)) {
            return "Speaker \(n + 1)"
        }
        return sp
    }

    // MARK: JSON parsing (from ownscribe --stream-transcript patch)

    /// Try to parse a JSON line from ownscribe's streaming output into a TranscriptLine
    static func fromJSON(_ line: String) -> TranscriptLine? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["type"] as? String == "transcript_chunk",
              let text = json["text"] as? String,
              let ts = json["start"] as? Double
        else { return nil }

        let speaker = json["speaker"] as? String
        return TranscriptLine(text: text, timestamp: ts, speaker: speaker)
    }

    // MARK: Markdown parsing (from stored transcript.md)

    /// Parse stored transcript.md into an array of TranscriptLines.
    /// ownscribe format: `[MM:SS] SPEAKER: text`
    static func parseMarkdown(_ markdown: String) -> [TranscriptLine] {
        var lines: [TranscriptLine] = []
        let pattern = #/^\[(\d+):(\d+)\]\s+(?:([^:]+):\s+)?(.+)$/#

        for raw in markdown.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let match = trimmed.firstMatch(of: pattern) {
                let minutes = Double(match.1) ?? 0
                let seconds = Double(match.2) ?? 0
                let ts = minutes * 60 + seconds
                let speaker = match.3.map { String($0).trimmingCharacters(in: .whitespaces) }
                let text = String(match.4).trimmingCharacters(in: .whitespaces)
                lines.append(TranscriptLine(text: text, timestamp: ts, speaker: speaker))
            } else if !lines.isEmpty {
                // continuation of previous line
                var last = lines.removeLast()
                last = TranscriptLine(text: last.text + " " + trimmed, timestamp: last.timestamp, speaker: last.speaker)
                lines.append(last)
            }
        }
        return lines
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: TranscriptLine, rhs: TranscriptLine) -> Bool { lhs.id == rhs.id }
}
