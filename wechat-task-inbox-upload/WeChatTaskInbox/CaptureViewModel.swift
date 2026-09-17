import CryptoKit
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
    private let processedClipboardHashesKey = "processedClipboardHashes"
    private let maximumStoredHashes = 100

    func processClipboard() async {
        if case .processing = state { return }

        guard let clipboardText = UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !clipboardText.isEmpty else {
            state = .failed("剪贴板里没有可处理的文字。请先在微信复制一条消息。")
            return
        }

        let clipboardHash = fingerprint(for: clipboardText)
        guard !processedClipboardHashes.contains(clipboardHash) else {
            state = .duplicate
            return
        }

        state = .processing
        let task = await classifier.classify(clipboardText)

        guard task.actionable else {
            state = .ignored("这条消息看起来不是需要你处理的事项，因此没有保存。")
            return
        }

        do {
            try await reminderStore.save(task)
            remember(clipboardHash)
            state = .saved(task)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private var processedClipboardHashes: [String] {
        UserDefaults.standard.stringArray(forKey: processedClipboardHashesKey) ?? []
    }

    private func remember(_ hash: String) {
        let updated = Array(([hash] + processedClipboardHashes.filter { $0 != hash })
            .prefix(maximumStoredHashes))
        UserDefaults.standard.set(updated, forKey: processedClipboardHashesKey)
    }

    private func fingerprint(for text: String) -> String {
        let canonicalText = text
            .precomposedStringWithCanonicalMapping
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return SHA256.hash(data: Data(canonicalText.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
