import SwiftUI

// MARK: – SessionView

/// Detail view for a completed recording session.
/// Left: AI-enhanced notes (editable). Right: full transcript.
struct SessionView: View {

    let session: Session
    @Environment(OwnScribeProcessManager.self) private var pm

    @State private var summaryText = ""
    @State private var transcriptLines: [TranscriptLine] = []
    @State private var selectedTab: DetailTab = .notes
    @State private var isSaving = false
    @State private var isRegenerating = false
    @State private var selectedTemplate = "meeting"

    enum DetailTab: String, CaseIterable {
        case notes = "Notes"
        case transcript = "Transcript"
        case userNotes = "Your Notes"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            sessionHeader

            Divider()

            // Content
            tabContent
        }
        .toolbar { toolbarItems }
        .onAppear { loadContent() }
    }

    // MARK: – Header

    private var sessionHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.title2.weight(.semibold))
                HStack(spacing: 8) {
                    Text(session.date, style: .date)
                    Text(session.date, style: .time)
                    if let dur = session.formattedDuration {
                        Text("·")
                        Text(dur)
                    }
                    if let event = session.calendarEventTitle {
                        Text("·")
                        Label(event, systemImage: "calendar")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                Button {
                    ExportManager.shared.copyToClipboard(session: session)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }

                Menu {
                    Button("Export Markdown…") {
                        Task { await ExportManager.shared.exportToFile(session: session, type: .markdown) }
                    }
                    Button("Export Transcript…") {
                        Task { await ExportManager.shared.exportToFile(session: session, type: .transcript) }
                    }
                    Button("Export JSON…") {
                        Task { await ExportManager.shared.exportToFile(session: session, type: .json) }
                    }
                    Button("Export PDF…") {
                        Task { await ExportManager.shared.exportToFile(session: session, type: .pdf) }
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }

                Menu {
                    ForEach(AppSettings.MeetingTemplate.allCases, id: \.self) { tmpl in
                        Button("Regenerate as \(tmpl.displayName)") {
                            Task { await regenerate(template: tmpl.rawValue) }
                        }
                    }
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise.circle")
                }
                .disabled(isRegenerating || !session.hasTranscript)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(16)
        .background(.regularMaterial)
    }

    // MARK: – Tabs

    private var tabContent: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            switch selectedTab {
            case .notes:
                notesEditor
            case .transcript:
                transcriptView
            case .userNotes:
                userNotesView
            }
        }
    }

    // MARK: – Notes editor (AI-enhanced, editable)

    private var notesEditor: some View {
        VStack(spacing: 0) {
            if isRegenerating {
                ProgressView("Regenerating notes…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if summaryText.isEmpty && !session.hasSummary {
                VStack(spacing: 12) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Notes are being processed…")
                        .foregroundStyle(.secondary)
                    Button("Refresh") { loadContent() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextEditor(text: $summaryText)
                    .font(.callout)
                    .padding(16)

                Divider()

                HStack {
                    Text("Edit notes, then save. Changes are persisted to disk.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if isSaving {
                        ProgressView().controlSize(.small)
                    }
                    Button("Save") { saveNotes() }
                        .disabled(isSaving)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: – Full transcript (read-only)

    private var transcriptView: some View {
        Group {
            if transcriptLines.isEmpty {
                if session.hasTranscript {
                    ProgressView("Loading transcript…")
                } else {
                    Text("No transcript available.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(transcriptLines) { line in
                            HStack(alignment: .top, spacing: 12) {
                                Text(line.formattedTimestamp)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 44, alignment: .trailing)

                                VStack(alignment: .leading, spacing: 2) {
                                    if !line.speakerDisplayName.isEmpty {
                                        Text(line.speakerDisplayName)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(line.text)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: – User notes (read-only reminder of what you typed during the call)

    private var userNotesView: some View {
        let notes = session.userNotesText()
        return Group {
            if notes.isEmpty {
                Text("No notes were taken during this session.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(notes)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            }
        }
    }

    // MARK: – Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem {
            Button("Save") { saveNotes() }
                .disabled(selectedTab != .notes || isSaving)
                .keyboardShortcut("s", modifiers: .command)
        }
    }

    // MARK: – Actions

    private func loadContent() {
        summaryText = session.summaryText()
        if session.hasTranscript {
            let raw = session.transcriptText()
            transcriptLines = TranscriptLine.parseMarkdown(raw)
        }
    }

    private func saveNotes() {
        isSaving = true
        do {
            try SessionStore.shared.saveSummary(summaryText, for: session)
        } catch {
            // In a real app, show an error alert
        }
        isSaving = false
    }

    private func regenerate(template: String) async {
        isRegenerating = true
        defer { isRegenerating = false }
        do {
            try await pm.resummarize(session: session, template: template)
            // Give ownscribe a moment to finish writing the file
            try? await Task.sleep(for: .seconds(2))
            loadContent()
        } catch {
            // Show error
        }
    }
}
