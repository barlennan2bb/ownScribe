import Foundation
import UserNotifications
import EventKit
import Observation

// MARK: – NotificationManager

/// Handles macOS notifications for upcoming calendar events.
/// Posts an actionable alert 2 minutes before a meeting starts with a
/// "Start Recording" button that kicks off ownscribe immediately.
@MainActor
@Observable
final class NotificationManager: NSObject {

    static let shared = NotificationManager()

    var authorizationStatus: UNAuthorizationStatus = .notDetermined

    // Track which event IDs have already been notified to avoid duplicates
    private var notifiedEventIDs = Set<String>()

    // Category / action identifiers
    static let categoryID        = "OWNMEET_MEETING_STARTING"
    static let startActionID     = "START_RECORDING"
    static let dismissActionID   = "DISMISS"

    // MARK: – Setup

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshAuthStatus() }
        registerCategories()
    }

    // MARK: – Authorization

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            authorizationStatus = granted ? .authorized : .denied
        } catch {
            authorizationStatus = .denied
        }
    }

    func refreshAuthStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    var isAuthorized: Bool { authorizationStatus == .authorized }

    // MARK: – Schedule a meeting notification

    /// Call this when a calendar event is detected as starting soon.
    /// Safe to call repeatedly — duplicate notifications are suppressed.
    func notifyMeetingStartingSoon(_ event: EKEvent) {
        let id = event.eventIdentifier ?? event.title ?? UUID().uuidString
        guard !notifiedEventIDs.contains(id) else { return }
        notifiedEventIDs.insert(id)

        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Meeting starting soon"
        content.body = "\(event.title ?? "Meeting") starts in ~2 minutes. Start recording?"
        content.categoryIdentifier = Self.categoryID
        content.sound = .default
        // Stash event title so the action handler can tag the session
        content.userInfo = ["eventTitle": event.title ?? "", "eventID": id]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "meeting-\(id)", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("[OwnMeet] Notification error: \(error)") }
        }
    }

    /// Clear a stale event ID so it can be re-notified next occurrence (e.g. next day)
    func clearNotifiedEvent(_ id: String) {
        notifiedEventIDs.remove(id)
    }

    // MARK: – Private

    private func registerCategories() {
        let startAction = UNNotificationAction(
            identifier: Self.startActionID,
            title: "Start Recording",
            options: [.foreground]
        )
        let dismissAction = UNNotificationAction(
            identifier: Self.dismissActionID,
            title: "Dismiss",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [startAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}

// MARK: – UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {

    /// Show notifications even while the app is in the foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }

    /// Handle action button taps
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == "START_RECORDING" else { return }

        let userInfo  = response.notification.request.content.userInfo
        let eventTitle = userInfo["eventTitle"] as? String

        await MainActor.run {
            Task { @MainActor in
                await OwnScribeProcessManager.shared.startRecording(
                    calendarEventTitle: eventTitle
                )
            }
        }
    }
}
