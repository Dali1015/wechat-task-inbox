import EventKit
import Foundation

@MainActor
final class ReminderStore {
    private let eventStore = EKEventStore()

    func save(_ task: CapturedTask) async throws {
        let granted = try await eventStore.requestFullAccessToReminders()
        guard granted else { throw ReminderStoreError.accessDenied }
        guard let calendar = eventStore.defaultCalendarForNewReminders() else {
            throw ReminderStoreError.missingDefaultList
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = calendar
        reminder.title = task.title
        reminder.notes = task.notes

        if let dueDate = task.dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }

        try eventStore.save(reminder, commit: true)
    }
}

enum ReminderStoreError: LocalizedError {
    case accessDenied
    case missingDefaultList

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "需要允许访问提醒事项，才能保存任务。"
        case .missingDefaultList:
            return "没有找到默认提醒事项列表。请先在系统提醒事项 App 中创建一个列表。"
        }
    }
}
