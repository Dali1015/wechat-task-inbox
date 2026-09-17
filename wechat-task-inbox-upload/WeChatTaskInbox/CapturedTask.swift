import Foundation

struct CapturedTask: Equatable {
    let actionable: Bool
    let title: String
    let notes: String
    let dueDate: Date?
    let confidence: Double
    let source: Source

    enum Source: String {
        case appleIntelligence = "设备端智能"
        case localRules = "本地规则"
    }

    static func ignored(notes: String, source: Source) -> CapturedTask {
        CapturedTask(
            actionable: false,
            title: "",
            notes: notes,
            dueDate: nil,
            confidence: 1,
            source: source
        )
    }
}
