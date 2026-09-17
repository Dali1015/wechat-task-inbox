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
        let title = decoded.title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !decoded.actionable || !title.isEmpty else {
            return classifyWithRules(text, now: now)
        }

        let fallbackDate = ChineseDateParser.date(in: text, relativeTo: now)
        return CapturedTask(
            actionable: decoded.actionable,
            title: title,
            notes: decoded.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "微信原文：\n\(text)"
                : decoded.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: decoded.dueAt.flatMap(parseISO8601Date) ?? fallbackDate,
            confidence: min(max(decoded.confidence, 0), 1),
            source: .appleIntelligence
        )
    }

    @available(iOS 26.0, *)
    private func decodeModelResponse(_ raw: String) throws -> ModelResponse {
        let fence = String(repeating: String(UnicodeScalar(96)!), count: 3)
        let withoutFences = raw
            .replacingOccurrences(of: fence + "json", with: "")
            .replacingOccurrences(of: fence, with: "")
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
        let dueDate = ChineseDateParser.date(in: normalized, relativeTo: now)
        let actionWords = [
            "提交", "发送", "发给", "回复", "跟进", "购买", "预约", "开会", "处理",
            "完成", "安排", "联系", "付款", "缴费", "确认", "下单", "订票", "报名",
            "参加", "拜访", "准备", "整理", "修改", "交付", "反馈", "查看", "提醒"
        ]
        let reminderWords = ["记得", "别忘了", "提醒我", "需要你"]
        let hasActionWord = actionWords.contains { normalized.contains($0) }
        let hasReminderIntent = reminderWords.contains { normalized.contains($0) }
        let actionable = hasActionWord || (hasReminderIntent && dueDate != nil)

        guard actionable else {
            return .ignored(notes: normalized, source: .localRules)
        }

        let confidence = dueDate == nil ? 0.68 : 0.82
        let prefix = confidence < 0.7 ? "[待确认] " : ""

        return CapturedTask(
            actionable: true,
            title: prefix + compactTitle(from: normalized),
            notes: "微信原文：\n\(normalized)",
            dueDate: dueDate,
            confidence: confidence,
            source: .localRules
        )
    }

    private func compactTitle(from text: String) -> String {
        var result = text.replacingOccurrences(
            of: #"^(?:(?:今天|明天|后天|今早|今晚|明早|明晚|(?:本|下)?(?:周|星期|礼拜)[一二三四五六日天])(?:上午|下午|晚上|中午|早上|凌晨)?(?:[0-9零〇一二三四五六七八九十两]+(?:点|时)(?:[0-9零〇一二三四五六七八九十两]+分?|半)?)?(?:前|之前|截止)?[，,、:：\s]*)?"#,
            with: "",
            options: .regularExpression
        )

        for prefix in ["麻烦你", "麻烦", "请你", "请", "帮我", "记得", "提醒我", "需要你"] {
            if result.hasPrefix(prefix) {
                result.removeFirst(prefix.count)
                result = result.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let title = String(result.prefix(60))
        return title.isEmpty ? "处理微信事项" : title
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

        let hasRelativeDate = ["今天", "明天", "后天", "今早", "今晚", "明早", "明晚"].contains {
            text.contains($0)
        }
        let hasNextWeekPrefix = ["下周", "下星期", "下礼拜"].contains { text.contains($0) }
        let explicitDate = calendarDate(in: text, calendar: calendar, now: now)
        let weekdayValue = weekday(in: text)

        let day: Date?
        let usesWeekday: Bool
        if let explicitDate {
            day = explicitDate
            usesWeekday = false
        } else if text.contains("后天") {
            day = calendar.date(byAdding: .day, value: 2, to: now)
            usesWeekday = false
        } else if text.contains("明天") || text.contains("明早") || text.contains("明晚") {
            day = calendar.date(byAdding: .day, value: 1, to: now)
            usesWeekday = false
        } else if text.contains("今天") || text.contains("今早") || text.contains("今晚") {
            day = now
            usesWeekday = false
        } else if let weekdayValue {
            day = next(weekday: weekdayValue, in: calendar, after: now, nextWeek: hasNextWeekPrefix)
            usesWeekday = true
        } else if time(in: text) != nil {
            day = now
            usesWeekday = false
        } else {
            day = nil
            usesWeekday = false
        }

        guard let day else { return nil }
        let clock = time(in: text) ?? defaultTime(in: text)
        guard var date = calendar.date(bySettingHour: clock.0, minute: clock.1, second: 0, of: day) else {
            return day
        }

        if date < now {
            if usesWeekday && !hasNextWeekPrefix {
                date = calendar.date(byAdding: .day, value: 7, to: date) ?? date
            } else if explicitDate == nil && !hasRelativeDate {
                date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            }
        }
        return date
    }

    private static func calendarDate(in text: String, calendar: Calendar, now: Date) -> Date? {
        guard let expression = try? NSRegularExpression(pattern: #"(?:(\d{4})年)?(\d{1,2})月(\d{1,2})(?:日|号)?"#),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let monthRange = Range(match.range(at: 2), in: text),
              let dayRange = Range(match.range(at: 3), in: text),
              let month = Int(text[monthRange]),
              let day = Int(text[dayRange]) else {
            return nil
        }

        let yearRange = Range(match.range(at: 1), in: text)
        var year = yearRange.flatMap { Int(text[$0]) } ?? calendar.component(.year, from: now)

        func makeDate(_ year: Int) -> Date? {
            var components = DateComponents()
            components.timeZone = calendar.timeZone
            components.year = year
            components.month = month
            components.day = day
            return calendar.date(from: components)
        }

        guard var result = makeDate(year) else { return nil }
        if yearRange == nil, result < calendar.startOfDay(for: now) {
            year += 1
            result = makeDate(year) ?? result
        }
        return result
    }

    private static func weekday(in text: String) -> Int? {
        let mapping: [Character: Int] = [
            "日": 1, "天": 1, "一": 2, "二": 3, "三": 4,
            "四": 5, "五": 6, "六": 7
        ]
        guard let expression = try? NSRegularExpression(pattern: #"(?:本|下)?(?:周|星期|礼拜)([一二三四五六日天])"#),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let character = text[range].first else {
            return nil
        }
        return mapping[character]
    }

    private static func next(weekday: Int, in calendar: Calendar, after now: Date, nextWeek: Bool) -> Date? {
        let current = calendar.component(.weekday, from: now)
        var offset = weekday - current
        if offset < 0 { offset += 7 }
        if nextWeek { offset += 7 }
        return calendar.date(byAdding: .day, value: offset, to: now)
    }

    private static func time(in text: String) -> (Int, Int)? {
        guard let expression = try? NSRegularExpression(
            pattern: #"(上午|下午|晚上|中午|早上|凌晨)?\s*(\d{1,2}|[零〇一二三四五六七八九十两]{1,3})(?:点|时|:|：)(?:(\d{1,2}|[零〇一二三四五六七八九十两]{1,3})(?:分)?)?(半)?"#
        ),
        let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
        let hourRange = Range(match.range(at: 2), in: text),
        let hour = number(from: String(text[hourRange])) else {
            return nil
        }

        let period = Range(match.range(at: 1), in: text).map { String(text[$0]) } ?? ""
        let minute = Range(match.range(at: 3), in: text).flatMap { number(from: String(text[$0])) }
            ?? (Range(match.range(at: 4), in: text) == nil ? 0 : 30)

        var adjustedHour = hour
        if ["下午", "晚上"].contains(period), hour < 12 {
            adjustedHour += 12
        } else if period == "中午", (1...5).contains(hour) {
            adjustedHour += 12
        } else if period == "凌晨", hour == 12 {
            adjustedHour = 0
        }

        guard (0...23).contains(adjustedHour), (0...59).contains(minute) else { return nil }
        return (adjustedHour, minute)
    }

    private static func defaultTime(in text: String) -> (Int, Int) {
        if text.contains("早上") || text.contains("今早") || text.contains("明早") || text.contains("上午") {
            return (9, 0)
        }
        if text.contains("下午") {
            return (14, 0)
        }
        if text.contains("晚上") || text.contains("今晚") || text.contains("明晚") {
            return (20, 0)
        }
        if text.contains("中午") {
            return (12, 0)
        }
        return (9, 0)
    }

    private static func number(from text: String) -> Int? {
        if let value = Int(text) { return value }

        let digits: [Character: Int] = [
            "零": 0, "〇": 0, "一": 1, "二": 2, "三": 3, "四": 4,
            "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "两": 2
        ]
        let characters = Array(text)
        guard let tenIndex = characters.firstIndex(of: "十") else {
            return characters.count == 1 ? digits[characters[0]] : nil
        }

        let tens = tenIndex == 0 ? 1 : (digits[characters[tenIndex - 1]] ?? 0)
        let ones = tenIndex == characters.count - 1 ? 0 : (digits[characters[tenIndex + 1]] ?? 0)
        return tens * 10 + ones
    }
}
