import Foundation
import EventKit
import Observation

// MARK: – CalendarManager

/// Reads macOS calendar via EventKit. Shows today's meetings and optionally
/// auto-prompts the user to start recording when one begins.
@MainActor
@Observable
final class CalendarManager {

    static let shared = CalendarManager()

    var authorizationStatus: EKAuthorizationStatus = .notDetermined
    var todaysEvents: [EKEvent] = []
    var nextEvent: EKEvent?
    var upcomingEventStartingSoon: EKEvent?   // event starting within 2 minutes

    private let store = EKEventStore()
    private var refreshTimer: Timer?

    // MARK: – Init

    init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        if authorizationStatus == .fullAccess {
            Task { await refreshEvents() }
            startRefreshTimer()
        }
    }

    // MARK: – Authorization

    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            authorizationStatus = granted ? .fullAccess : .denied
            if granted {
                await refreshEvents()
                startRefreshTimer()
            }
        } catch {
            authorizationStatus = .denied
        }
    }

    // MARK: – Event fetching

    func refreshEvents() async {
        guard authorizationStatus == .fullAccess else { return }

        let cal = Calendar.current
        let now = Date()
        let startOfDay = cal.startOfDay(for: now)
        let endOfDay   = cal.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }

        todaysEvents = events
        nextEvent = events.first(where: { $0.startDate > now })
        upcomingEventStartingSoon = events.first(where: {
            $0.startDate > now && $0.startDate.timeIntervalSinceNow < 120
        })
    }

    // MARK: – Helpers

    var hasCalendarAccess: Bool { authorizationStatus == .fullAccess }

    func formattedTime(for event: EKEvent) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        return "\(fmt.string(from: event.startDate)) – \(fmt.string(from: event.endDate))"
    }

    func attendeeNames(for event: EKEvent) -> String {
        guard let attendees = event.attendees, !attendees.isEmpty else { return "" }
        return attendees
            .compactMap { $0.name }
            .prefix(4)
            .joined(separator: ", ")
    }

    // MARK: – Private

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshEvents()
            }
        }
    }
}
