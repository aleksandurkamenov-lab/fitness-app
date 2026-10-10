import Foundation
import Observation
import UserNotifications

/// Таймер за почивка. Известява и при заключен телефон чрез локално известие.
@Observable
final class RestTimer {
    private(set) var endDate: Date?
    private(set) var duration: TimeInterval = 0
    private let notificationID = "rest-timer"

    var isRunning: Bool {
        guard let endDate else { return false }
        return endDate > .now
    }

    func start(seconds: Int) {
        duration = TimeInterval(seconds)
        endDate = Date.now.addingTimeInterval(duration)
        scheduleNotification(after: duration)
    }

    func add(seconds: Int) {
        guard let endDate else { return }
        let newEnd = max(endDate, .now).addingTimeInterval(TimeInterval(seconds))
        self.endDate = newEnd
        duration += TimeInterval(seconds)
        scheduleNotification(after: newEnd.timeIntervalSinceNow)
    }

    func stop() {
        endDate = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
    }

    func remaining(at date: Date) -> TimeInterval {
        guard let endDate else { return 0 }
        return max(endDate.timeIntervalSince(date), 0)
    }

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func scheduleNotification(after interval: TimeInterval) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        guard interval > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Почивката свърши"
        content.body = "Време е за следващата серия."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger))
    }
}
