import SwiftUI
import UIKit

@MainActor
final class CaptureViewModel: ObservableObject {
    enum State {
        case ready
        case processing
        case saved(CapturedTask)
        case ignored(String)
        case duplicate
        case failed(String)
    }

    @Published private(set) var state: State = .ready

    private let classifier = TaskClassifier()
    private let reminderStore = ReminderStore()
    private let storedChangeCountKey = "lastProcessedClipboardChangeCount"

    func processClipboard(allowDuplicate: Bool = false) async {
        guard let text = UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            state = .failed("剪贴板里没有可处理的文字。请先在微信复制一条消息。")
            return
        }

        let changeCount = UIPasteboard.general.changeCount
        let previousChangeCount = UserDefaults.standard.integer(forKey: storedChangeCountKey)
        guard allowDuplicate || previousChangeCount != changeCount else {
            state = .duplicate
            return
        }

        state = .processing
        let task = await classifier.classify(text)

        guard task.actionable else {
            UserDefaults.standard.set(changeCount, forKey: storedChangeCountKey)
            state = .ignored("这条消息看起来不是需要你处理的事项，因此没有保存。")
            return
        }

        do {
            try await reminderStore.save(task)
            UserDefaults.standard.set(changeCount, forKey: storedChangeCountKey)
            state = .saved(task)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
