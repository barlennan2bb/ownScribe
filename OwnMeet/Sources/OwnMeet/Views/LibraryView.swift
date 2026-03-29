import SwiftUI
import EventKit

// MARK: – LibraryView

/// The main OwnMeet window: session list on the left, detail on the right.
struct LibraryView: View {

    @Environment(OwnScribeProcessManager.self) private var pm
    @Environment(SessionStore.self) private var store
    @Environment(CalendarManager.self) private var calendar
    @Environment(OwnScribeInstaller.self) private var installer
    @Environment(AppSettings.self) private var settings

    @State private var selectedSession: Session?
    @State private var searchText = ""
    @State private var askText = ""
    @State private var askResult = ""
    @State private var isAsking = false
    @State private var showOnboarding = false
    @State private var showDeleteAlert = false
    @State private var sessionToDelete: Session?

    var body: some View {
        NavigationSplitView {
            sidebarView
        } detail: {
            detailView
        }
        .navigationTitle("OwnMeet")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
                .environment(installer)
                .environment(settings)
                .environment(calendar)
        }
        .alert("Delete Session?", isPresented: $showDeleteAlert, presenting: sessionToDelete) { session in
            Button("Delete", role: .destructive) { try? store.delete(session) }
            Button("Cancel", role: .cancel) {}
        } message: { session in
            Text("'\(session.title)' will be permanently deleted from disk.")
        }
        .onAppear {
            if !settings.hasCompletedOnboarding { showOnboarding = true }
            Task { await installer.check() }
        }
    }

    // MARK: – Sidebar

    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Search / Ask bar
            searchBar
                .padding(.horizontal, 12)
                .padding(.top, 8)

            // Today's calendar events (if access granted)
            if calendar.hasCalendarAccess && !calendar.todaysEvents.isEmpty {
                calendarSection
            }

            Divider().padding(.top, 8)

            // Session list
            if store.isLoading {
                ProgressView("Loading sessions…").padding()
            } else if filteredSessions.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search sessions or ask a question", text: $searchText)
                .textFieldStyle(.plain)
                .onSubmit {
                    if searchText.hasPrefix("?") || searchText.hasPrefix("ask:") {
                        let q = searchText.replacingOccurrences(of: "^[?]|^ask:", with: "", options: .regularExpression)
                        Task { await runAsk(question: q.trimmingCharacters(in: .whitespaces)) }
                    }
                }
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            ForEach(calendar.todaysEvents.prefix(5), id: \.eventIdentifier) { event in
                calendarEventRow(event)
            }
        }
    }

    private func calendarEventRow(_ event: EKEvent) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(cgColor: event.calendar.cgColor))
                .frame(width: 3, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title ?? "Meeting")
                    .font(.callout)
                    .lineLimit(1)
                Text(calendar.formattedTime(for: event))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if event.startDate.timeIntervalSinceNow < 120 && event.startDate > Date() {
                Button("Record") {
                    Task { await pm.startRecording(calendarEventTitle: event.title) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var sessionList: some View {
        List(filteredSessions, selection: $selectedSession) { session in
            SessionRowView(session: session)
                .tag(session)
                .contextMenu {
                    Button("Copy Summary") {
                        ExportManager.shared.copyToClipboard(session: session)
                    }
                    Button("Export…") {
                        Task { await ExportManager.shared.exportToFile(session: session, type: .markdown) }
                    }
                    Divider()
                    Button("Delete…", role: .destructive) {
                        sessionToDelete = session
                        showDeleteAlert = true
                    }
                }
        }
        .listStyle(.sidebar)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("No sessions yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Press ⌘⇧R to start recording a meeting or phone call.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: – Detail

    @ViewBuilder
    private var detailView: some View {
        if pm.isRecording || pm.isSummarizing {
            LiveRecordingView()
                .environment(pm)
        } else if !askResult.isEmpty {
            askResultView
        } else if let session = selectedSession {
            SessionView(session: session)
                .environment(pm)
                .id(session.id)
        } else {
            welcomeDetail
        }
    }

    private var askResultView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Answer", systemImage: "sparkles")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button("Clear") { askResult = ""; searchText = "" }
                }
                Text(askResult)
                    .textSelection(.enabled)
            }
            .padding(24)
        }
    }

    private var welcomeDetail: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("OwnMeet")
                .font(.largeTitle.weight(.bold))
            Text("Local-first, bot-free meeting notes.")
                .font(.title3)
                .foregroundStyle(.secondary)

            if !installer.isReady {
                installPrompt
            } else {
                Button {
                    Task { await pm.startRecording() }
                } label: {
                    Label("Start Recording", systemImage: "waveform.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var installPrompt: some View {
        VStack(spacing: 12) {
            switch installer.state {
            case .checking:
                ProgressView("Checking for ownscribe…")
            case .uvxMissing:
                VStack(spacing: 8) {
                    Text("ownscribe requires `uv` to be installed.")
                        .foregroundStyle(.secondary)
                    Button("Install uv via Homebrew") {
                        Task { await installer.installUV() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .installing:
                ProgressView("Installing…")
            case .failed(let reason):
                Label(reason, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            case .ready:
                EmptyView()
            }
        }
    }

    // MARK: – Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if pm.isRecording {
                Button {
                    pm.stopRecording()
                } label: {
                    Label("Stop", systemImage: "stop.circle.fill")
                        .foregroundStyle(.red)
                }
            } else {
                Button {
                    Task { await pm.startRecording() }
                } label: {
                    Label("Record", systemImage: "waveform.circle.fill")
                }
                .disabled(!pm.isIdle)
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        ToolbarItem(placement: .automatic) {
            Button {
                Task { await store.reload() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
    }

    // MARK: – Filtering + Ask

    private var filteredSessions: [Session] {
        guard !searchText.isEmpty else { return store.sessions }
        let q = searchText.lowercased()
        return store.sessions.filter {
            $0.title.lowercased().contains(q) ||
            $0.calendarEventTitle?.lowercased().contains(q) == true
        }
    }

    private func runAsk(question: String) async {
        guard !question.isEmpty else { return }
        isAsking = true
        defer { isAsking = false }
        do {
            askResult = try await pm.ask(question: question)
        } catch {
            askResult = "Error: \(error.localizedDescription)"
        }
    }
}

// MARK: – SessionRowView

private struct SessionRowView: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title)
                .font(.callout.weight(.medium))
                .lineLimit(2)

            HStack(spacing: 6) {
                Text(session.date, style: .date)
                if let dur = session.formattedDuration, !dur.isEmpty {
                    Text("·")
                    Text(dur)
                }
                if !session.hasSummary {
                    Text("·")
                    Text("processing…")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
