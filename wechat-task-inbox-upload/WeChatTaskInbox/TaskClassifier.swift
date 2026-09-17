import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct TaskClassifier {
    func classify(_ text: String, now: Date = .now) async -> CapturedTask {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            do {
                return try await classifyWithAppleIntelligence(text, now: now)
            } catch {
                // The local fallback keeps capture working if the system model declines a request.
            }
        }
        #endif

        return classifyWithRules(text, now: now)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func classifyWithAppleIntelligence(_ text: String, now: Date) async throws -> CapturedTask {
        let session = LanguageModelSession(instructions: """
        You extract a single actionable personal task from Chinese chat text.
        A task is something the phone owner needs to do, attend, reply to, follow up on, buy,
        submit, or remember. Ignore acknowledgements, casual chat, advertisements, and status-only messages.
        Never invent people, dates, places, or times. Interpret relative Chinese dates using the supplied current time.
        Return only valid JSON with this exact schema:
        {"actionable":true,"title":"short task title","notes":"brief useful details","dueAt":"ISO-8601 date or null","confidence":0.0}
        """)

        let formatter = ISO8601DateFormatter()
        let prompt = """
        Current time: \(formatter.string(from: now))
        Current time zone: \(TimeZone.current.identifier)
        Chat text: \(text)
        """
        let response = try await session.respond(to: prompt)
        let decoded = try decodeModelResponse(response.content)

        return CapturedTask(
            actionable: decoded.actionable,
            title: decoded.title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: decoded.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: decoded.dueAt.flatMap(parseISO8601Date),
            confidence: decoded.confidence,
            source: .appleIntelligence
        )
    }

    @available(iOS 26.0, *)
    private func decodeModelResponse(_ raw: String) throws -> ModelResponse {
        let withoutFences = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = withoutFences.firstIndex(of: "{"),
              let last = withoutFences.lastIndex(of: "}") else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "No JSON object"))
        }
        let json = String(withoutFences[first...last])
        return try JSONDecoder().decode(ModelResponse.self, from: Data(json.utf8))
    }
    #endif

    private func classifyWithRules(_ text: String, now: Date) -> CapturedTask {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskWords = ["请", "帮我", "需要", "记得", "提交", "发送", "发给", "回复", "跟进", "购买", "买", "预约", "开会", "处理", "完成", "安排", "联系", "付款", "缴费", "确认", "订"]
        let actionable = taskWords.contains { normalized.contains($0) }

        guard actionable else {
            return .ignored(notes: normalized, source: .localRules)
        }

        let dueDate = ChineseDateParser.date(in: normalized, relativeTo: now)
        let title = compactTitle(from: normalized)
        let confidence = dueDate == nil ? 0.66 : 0.78
        let prefix = confidence < 0.7 ? "[待确认] " : ""

        return CapturedTask(
            actionable: true,
            title: prefix + title,
            notes: "微信原文：\n\(normalized)",
            dueDate: dueDate,
            confidence: confidence,
            source: .localRules
        )
    }

    private func compactTitle(from text: String) -> String {
        let trimmed = text
            .replacingOccurrences(of: "请", with: "")
            .replacingOccurrences(of: "帮我", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(48))
    }

    private func parseISO8601Date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}

private struct ModelResponse: Decodable {
    let actionable: Bool
    let title: String
    let notes: String
    let dueAt: String?
    let confidence: Double
}

private enum ChineseDateParser {
    static func date(in text: String, relativeTo now: Date) -> Date? {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let day: Date?

        if text.contains("后天") {
            day = calendar.date(byAdding: .day, value: 2, to: now)
        } else if text.contains("明天") {
            day = calendar.date(byAdding: .day, value: 1, to: now)
        } else if text.contains("今天") {
            day = now
        } else if let weekday = weekday(in: text) {
            day = next(weekday: weekday, in: calendar, after: now, nextWeek: text.contains("下周"))
        } else if time(in: text) != nil {
            day = now
        } else {
            day = nil
        }

        guard var date = day else { return nil }
        let clock = time(in: text) ?? (9, 0)
        date = calendar.date(bySettingHour: clock.0, minute: clock.1, second: 0, of: date) ?? date

        if day != nil, !text.contains("今天"), !text.contains("明天"), !text.contains("后天"), weekday(in: text) == nil,
           date < now, time(in: text) != nil {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return date
    }

    private static func weekday(in text: String) -> Int? {
        let mapping: [Character: Int] = ["日": 1, "天": 1, "一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7]
        guard let expression = try? NSRegularExpression(pattern: "(?:下)?周([一二三四五六日天])"),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let character = text[range].first else { return nil }
        return mapping[character]
    }

    private static func next(weekday: Int, in calendar: Calendar, after now: Date, nextWeek: Bool) -> Date? {
        let current = calendar.component(.weekday, from: now)
        var offset = (weekday - current + 7) % 7
        if offset == 0 { offset = 7 }
        if nextWeek { offset += 7 }
        return calendar.date(byAdding: .day, value: offset, to: now)
    }

    private static func time(in text: String) -> (Int, Int)? {
        guard let expression = try? NSRegularExpression(pattern: "(?:(上午|下午|晚上|中午|早上))?\\s*(\\d{1,2})(?:点|:|：)(?:(\\d{1,2}))?"),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let hourRange = Range(match.range(at: 2), in: text),
              let hour = Int(text[hourRange]) else { return nil }

        let period = Range(match.range(at: 1), in: text).map { String(text[$0]) } ?? ""
        let minute = Range(match.range(at: 3), in: text).flatMap { Int(text[$0]) } ?? 0
        var adjustedHour = hour
        if ["下午", "晚上"].contains(period), hour < 12 { adjustedHour += 12 }
        if period == "中午", hour < 11 { adjustedHour += 12 }
        guard (0...23).contains(adjustedHour), (0...59).contains(minute) else { return nil }
        return (adjustedHour, minute)
    }
}
