import Foundation

enum NaturalRecurrenceFrequency {
    case daily
    case weekly
    case monthly
    case yearly
}

struct NaturalRecurrenceWeekday {
    let day: Int
    let weekNumber: Int?
}

struct NaturalRecurrence {
    let frequency: NaturalRecurrenceFrequency
    let interval: Int
    let label: String
    let weekdays: [NaturalRecurrenceWeekday]
}

struct NaturalRecurrenceParseResult {
    let title: String
    let date: Date
    let hasTime: Bool
    let recurrence: NaturalRecurrence
    let recognizedRange: NSRange
    let recognizedText: String
}

enum NaturalRecurrenceParser {
    private static let weekdays: [String: Int] = [
        "sunday": 1, "sun": 1, "monday": 2, "mon": 2,
        "tuesday": 3, "tue": 3, "tues": 3, "wednesday": 4, "wed": 4,
        "thursday": 5, "thu": 5, "thur": 5, "thurs": 5,
        "friday": 6, "fri": 6, "saturday": 7, "sat": 7
    ]

    private static let weekdayPattern = "sunday|sun|monday|mon|tuesday|tue|tues|wednesday|wed|thursday|thu|thur|thurs|friday|fri|saturday|sat"
    private static let timePattern = #"(?:noon|\d{1,2}(?::\d{2})?\s*(?:am|pm)|(?:[01]?\d|2[0-3]):[0-5]\d|(?:[01]\d|2[0-3])[0-5]\d)"#
    private static let everyPattern = #"(?:every|ev)"#

    static func parse(
        _ text: String,
        now: Date = Date(),
        calendar: Calendar = .current,
        excluding excludedRanges: [NSRange] = []
    ) -> NaturalRecurrenceParseResult? {
        if let result = parseWeekdaySet(text, now: now, calendar: calendar, excluding: excludedRanges) { return result }
        if let result = parseWeekend(text, now: now, calendar: calendar, excluding: excludedRanges) { return result }
        if let result = parseWeekdayList(text, now: now, calendar: calendar, excluding: excludedRanges) { return result }
        if let result = parseOrdinalWeekday(text, now: now, calendar: calendar, excluding: excludedRanges) { return result }
        if let result = parseOtherWeekday(text, now: now, calendar: calendar, excluding: excludedRanges) { return result }
        if let result = parseSingleWeekday(text, now: now, calendar: calendar, excluding: excludedRanges) { return result }
        if let result = parseNumericInterval(text, now: now, calendar: calendar, excluding: excludedRanges) { return result }
        if let result = parseOtherUnit(text, now: now, calendar: calendar, excluding: excludedRanges) { return result }
        if let result = parseEveryUnit(text, now: now, calendar: calendar, excluding: excludedRanges) { return result }
        if let result = parseFrequencyAlias(text, now: now, calendar: calendar, excluding: excludedRanges) { return result }
        if let result = parseQuarterly(text, now: now, calendar: calendar, excluding: excludedRanges) { return result }
        return parseDayOfMonth(text, now: now, calendar: calendar, excluding: excludedRanges)
    }

    private static func parseWeekdaySet(
        _ text: String,
        now: Date,
        calendar: Calendar,
        excluding excludedRanges: [NSRange]
    ) -> NaturalRecurrenceParseResult? {
        let pattern = #"\b"# + everyPattern + #"\s+(?:weekdays?|workdays?)(?:\s+(?:at\s+)?("# + timePattern + #"))?\b"#
        guard let match = firstMatch(pattern, in: text, excluding: excludedRanges) else { return nil }
        let days = [2, 3, 4, 5, 6]
        return weekdayResult(
            for: match,
            in: text,
            days: days,
            now: now,
            calendar: calendar,
            timeToken: capture(1, from: match, in: text),
            recurrence: NaturalRecurrence(
                frequency: .weekly,
                interval: 1,
                label: "Every weekday",
                weekdays: days.map { NaturalRecurrenceWeekday(day: $0, weekNumber: nil) }
            )
        )
    }

    private static func parseWeekend(
        _ text: String,
        now: Date,
        calendar: Calendar,
        excluding excludedRanges: [NSRange]
    ) -> NaturalRecurrenceParseResult? {
        let pattern = #"\b"# + everyPattern + #"\s+weekends?(?:\s+(?:at\s+)?("# + timePattern + #"))?\b"#
        guard let match = firstMatch(pattern, in: text, excluding: excludedRanges) else { return nil }
        let days = [7, 1]
        return weekdayResult(
            for: match,
            in: text,
            days: days,
            now: now,
            calendar: calendar,
            timeToken: capture(1, from: match, in: text),
            recurrence: NaturalRecurrence(
                frequency: .weekly,
                interval: 1,
                label: "Every weekend",
                weekdays: days.map { NaturalRecurrenceWeekday(day: $0, weekNumber: nil) }
            )
        )
    }

    private static func parseWeekdayList(
        _ text: String,
        now: Date,
        calendar: Calendar,
        excluding excludedRanges: [NSRange]
    ) -> NaturalRecurrenceParseResult? {
        let pattern = #"\b"# + everyPattern + #"\s+((?:"# + weekdayPattern + #")(?:\s*,\s*(?:"# + weekdayPattern + #"))+)(?:\s+(?:at\s+)?("# + timePattern + #"))?\b"#
        guard let match = firstMatch(pattern, in: text, excluding: excludedRanges),
              let tokens = capture(1, from: match, in: text)?.split(separator: ",") else { return nil }

        var days: [Int] = []
        for token in tokens {
            guard let day = weekdays[token.trimmingCharacters(in: .whitespaces).lowercased()] else { return nil }
            if !days.contains(day) { days.append(day) }
        }
        guard days.count >= 2 else { return nil }

        let names = days.map { fullWeekdayName($0) }
        return weekdayResult(
            for: match,
            in: text,
            days: days,
            now: now,
            calendar: calendar,
            timeToken: capture(2, from: match, in: text),
            recurrence: NaturalRecurrence(
                frequency: .weekly,
                interval: 1,
                label: "Every \(names.joined(separator: ", "))",
                weekdays: days.map { NaturalRecurrenceWeekday(day: $0, weekNumber: nil) }
            )
        )
    }

    private static func parseOrdinalWeekday(
        _ text: String,
        now: Date,
        calendar: Calendar,
        excluding excludedRanges: [NSRange]
    ) -> NaturalRecurrenceParseResult? {
        let ordinalPattern = "1st|2nd|3rd|4th|5th|first|second|third|fourth|fifth|last"
        let pattern = #"\b"# + everyPattern + #"\s+("# + ordinalPattern + #")\s+("# + weekdayPattern + #")(?:\s+(?:at\s+)?("# + timePattern + #"))?\b"#
        guard let match = firstMatch(pattern, in: text, excluding: excludedRanges),
              let ordinal = capture(1, from: match, in: text)?.lowercased(),
              let weekdayToken = capture(2, from: match, in: text)?.lowercased(),
              let day = weekdays[weekdayToken] else { return nil }

        let weekNumbers = [
            "1st": 1, "first": 1, "2nd": 2, "second": 2,
            "3rd": 3, "third": 3, "4th": 4, "fourth": 4,
            "5th": 5, "fifth": 5, "last": -1
        ]
        guard let weekNumber = weekNumbers[ordinal],
              let base = nthWeekdayDate(now, weekday: day, weekNumber: weekNumber, calendar: calendar) else { return nil }

        let timed = applyingTime(capture(3, from: match, in: text), to: base, calendar: calendar)
        let displayOrdinal = weekNumber == -1 ? "last" : ["", "1st", "2nd", "3rd", "4th", "5th"][weekNumber]
        return result(
            for: match,
            in: text,
            date: timed.date,
            hasTime: timed.hasTime,
            recurrence: NaturalRecurrence(
                frequency: .monthly,
                interval: 1,
                label: "Every \(displayOrdinal) \(fullWeekdayName(day))",
                weekdays: [NaturalRecurrenceWeekday(day: day, weekNumber: weekNumber)]
            )
        )
    }

    private static func parseOtherWeekday(
        _ text: String,
        now: Date,
        calendar: Calendar,
        excluding excludedRanges: [NSRange]
    ) -> NaturalRecurrenceParseResult? {
        let pattern = #"\b"# + everyPattern + #"\s+other\s+("# + weekdayPattern + #")(?:\s+(?:at\s+)?("# + timePattern + #"))?\b"#
        guard let match = firstMatch(pattern, in: text, excluding: excludedRanges),
              let token = capture(1, from: match, in: text),
              let day = weekdays[token.lowercased()],
              let base = nextWeekday(day, from: now, calendar: calendar, allowToday: true) else { return nil }
        return simpleResult(
            for: match,
            in: text,
            base: base,
            timeToken: capture(2, from: match, in: text),
            calendar: calendar,
            frequency: .weekly,
            interval: 2,
            label: "Every other \(token)"
        )
    }

    private static func parseSingleWeekday(
        _ text: String,
        now: Date,
        calendar: Calendar,
        excluding excludedRanges: [NSRange]
    ) -> NaturalRecurrenceParseResult? {
        let pattern = #"\b"# + everyPattern + #"\s+("# + weekdayPattern + #")(?:\s+(?:at\s+)?("# + timePattern + #"))?\b"#
        guard let match = firstMatch(pattern, in: text, excluding: excludedRanges),
              let token = capture(1, from: match, in: text),
              let day = weekdays[token.lowercased()],
              let base = nextWeekday(day, from: now, calendar: calendar, allowToday: true) else { return nil }
        return simpleResult(
            for: match,
            in: text,
            base: base,
            timeToken: capture(2, from: match, in: text),
            calendar: calendar,
            frequency: .weekly,
            interval: 1,
            label: "Every \(token)"
        )
    }

    private static func parseNumericInterval(
        _ text: String,
        now: Date,
        calendar: Calendar,
        excluding excludedRanges: [NSRange]
    ) -> NaturalRecurrenceParseResult? {
        let pattern = #"\b"# + everyPattern + #"\s+(\d+)\s+(days?|weeks?|months?|years?)(?:\s+(?:at\s+)?("# + timePattern + #"))?\b"#
        guard let match = firstMatch(pattern, in: text, excluding: excludedRanges),
              let intervalText = capture(1, from: match, in: text),
              let interval = Int(intervalText), (1...999).contains(interval),
              let unit = capture(2, from: match, in: text) else { return nil }
        return simpleResult(
            for: match,
            in: text,
            base: calendar.startOfDay(for: now),
            timeToken: capture(3, from: match, in: text),
            calendar: calendar,
            frequency: frequency(for: unit),
            interval: interval,
            label: "Every \(interval) \(unit)"
        )
    }

    private static func parseOtherUnit(
        _ text: String,
        now: Date,
        calendar: Calendar,
        excluding excludedRanges: [NSRange]
    ) -> NaturalRecurrenceParseResult? {
        let pattern = #"\b"# + everyPattern + #"\s+other\s+(day|week|month|year)(?:\s+(?:at\s+)?("# + timePattern + #"))?\b"#
        guard let match = firstMatch(pattern, in: text, excluding: excludedRanges),
              let unit = capture(1, from: match, in: text) else { return nil }
        return simpleResult(
            for: match,
            in: text,
            base: calendar.startOfDay(for: now),
            timeToken: capture(2, from: match, in: text),
            calendar: calendar,
            frequency: frequency(for: unit),
            interval: 2,
            label: "Every other \(unit.lowercased())"
        )
    }

    private static func parseEveryUnit(
        _ text: String,
        now: Date,
        calendar: Calendar,
        excluding excludedRanges: [NSRange]
    ) -> NaturalRecurrenceParseResult? {
        let pattern = #"\b"# + everyPattern + #"\s+(day|week|month|year)(?:\s+(?:at\s+)?("# + timePattern + #"))?\b"#
        guard let match = firstMatch(pattern, in: text, excluding: excludedRanges),
              let unit = capture(1, from: match, in: text) else { return nil }
        return simpleResult(
            for: match,
            in: text,
            base: calendar.startOfDay(for: now),
            timeToken: capture(2, from: match, in: text),
            calendar: calendar,
            frequency: frequency(for: unit),
            interval: 1,
            label: "Every \(unit.lowercased())"
        )
    }

    private static func parseFrequencyAlias(
        _ text: String,
        now: Date,
        calendar: Calendar,
        excluding excludedRanges: [NSRange]
    ) -> NaturalRecurrenceParseResult? {
        let pattern = #"\b(daily|weekly|monthly|yearly)(?:\s+(?:at\s+)?("# + timePattern + #"))?\b"#
        guard let match = firstMatch(pattern, in: text, excluding: excludedRanges),
              let token = capture(1, from: match, in: text) else { return nil }
        return simpleResult(
            for: match,
            in: text,
            base: calendar.startOfDay(for: now),
            timeToken: capture(2, from: match, in: text),
            calendar: calendar,
            frequency: frequency(for: token),
            interval: 1,
            label: token
        )
    }

    private static func parseQuarterly(
        _ text: String,
        now: Date,
        calendar: Calendar,
        excluding excludedRanges: [NSRange]
    ) -> NaturalRecurrenceParseResult? {
        let pattern = #"\b(?:quarterly|"# + everyPattern + #"\s+quarter)(?:\s+(?:at\s+)?("# + timePattern + #"))?\b"#
        guard let match = firstMatch(pattern, in: text, excluding: excludedRanges) else { return nil }
        return simpleResult(
            for: match,
            in: text,
            base: calendar.startOfDay(for: now),
            timeToken: capture(1, from: match, in: text),
            calendar: calendar,
            frequency: .monthly,
            interval: 3,
            label: "Every quarter"
        )
    }

    private static func parseDayOfMonth(
        _ text: String,
        now: Date,
        calendar: Calendar,
        excluding excludedRanges: [NSRange]
    ) -> NaturalRecurrenceParseResult? {
        let pattern = #"\b"# + everyPattern + #"\s+(\d{1,2})(?:st|nd|rd|th)(?:\s+(?:at\s+)?("# + timePattern + #"))?\b"#
        guard let match = firstMatch(pattern, in: text, excluding: excludedRanges),
              let dayText = capture(1, from: match, in: text),
              let day = Int(dayText), (1...31).contains(day),
              let base = nextDayOfMonth(day, from: now, calendar: calendar) else { return nil }
        return simpleResult(
            for: match,
            in: text,
            base: base,
            timeToken: capture(2, from: match, in: text),
            calendar: calendar,
            frequency: .monthly,
            interval: 1,
            label: "Every \(dayText)th"
        )
    }

    private static func weekdayResult(
        for match: NSTextCheckingResult,
        in text: String,
        days: [Int],
        now: Date,
        calendar: Calendar,
        timeToken: String?,
        recurrence: NaturalRecurrence
    ) -> NaturalRecurrenceParseResult? {
        guard let base = nextMatchingWeekday(days, from: now, calendar: calendar) else { return nil }
        let timed = applyingTime(timeToken, to: base, calendar: calendar)
        return result(for: match, in: text, date: timed.date, hasTime: timed.hasTime, recurrence: recurrence)
    }

    private static func simpleResult(
        for match: NSTextCheckingResult,
        in text: String,
        base: Date,
        timeToken: String?,
        calendar: Calendar,
        frequency: NaturalRecurrenceFrequency,
        interval: Int,
        label: String
    ) -> NaturalRecurrenceParseResult {
        let timed = applyingTime(timeToken, to: base, calendar: calendar)
        return result(
            for: match,
            in: text,
            date: timed.date,
            hasTime: timed.hasTime,
            recurrence: NaturalRecurrence(frequency: frequency, interval: interval, label: label, weekdays: [])
        )
    }

    private static func result(
        for match: NSTextCheckingResult,
        in text: String,
        date: Date,
        hasTime: Bool,
        recurrence: NaturalRecurrence
    ) -> NaturalRecurrenceParseResult {
        NaturalRecurrenceParseResult(
            title: removing(match.range, from: text),
            date: date,
            hasTime: hasTime,
            recurrence: recurrence,
            recognizedRange: match.range,
            recognizedText: (text as NSString).substring(with: match.range)
        )
    }

    private static func frequency(for unit: String) -> NaturalRecurrenceFrequency {
        let value = unit.lowercased()
        if value.hasPrefix("day") || value == "daily" { return .daily }
        if value.hasPrefix("week") { return .weekly }
        if value.hasPrefix("month") { return .monthly }
        return .yearly
    }

    private static func nextMatchingWeekday(_ weekdays: [Int], from date: Date, calendar: Calendar) -> Date? {
        let base = calendar.startOfDay(for: date)
        for offset in 0...7 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: base) else { continue }
            if weekdays.contains(calendar.component(.weekday, from: candidate)) { return candidate }
        }
        return nil
    }

    private static func nextWeekday(
        _ weekday: Int,
        from date: Date,
        calendar: Calendar,
        allowToday: Bool
    ) -> Date? {
        let base = calendar.startOfDay(for: date)
        let current = calendar.component(.weekday, from: base)
        var offset = (weekday - current + 7) % 7
        if offset == 0 && !allowToday { offset = 7 }
        return calendar.date(byAdding: .day, value: offset, to: base)
    }

    private static func nthWeekdayDate(
        _ date: Date,
        weekday: Int,
        weekNumber: Int,
        calendar: Calendar
    ) -> Date? {
        let base = calendar.startOfDay(for: date)
        let current = calendar.dateComponents([.year, .month], from: base)
        guard let currentMonth = calendar.date(from: DateComponents(year: current.year, month: current.month, day: 1)) else { return nil }

        for offset in 0..<24 {
            guard let monthStart = calendar.date(byAdding: .month, value: offset, to: currentMonth) else { continue }
            let candidate: Date?
            if weekNumber > 0 {
                let firstWeekday = calendar.component(.weekday, from: monthStart)
                let day = 1 + (weekday - firstWeekday + 7) % 7 + (weekNumber - 1) * 7
                let components = calendar.dateComponents([.year, .month], from: monthStart)
                candidate = calendar.date(from: DateComponents(year: components.year, month: components.month, day: day))
            } else {
                guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart),
                      let lastDay = calendar.date(byAdding: .day, value: -1, to: nextMonth) else { continue }
                let delta = (calendar.component(.weekday, from: lastDay) - weekday + 7) % 7
                candidate = calendar.date(byAdding: .day, value: -delta, to: lastDay)
            }

            guard let candidate else { continue }
            let candidateMonth = calendar.component(.month, from: candidate)
            let intendedMonth = calendar.component(.month, from: monthStart)
            if candidateMonth == intendedMonth, candidate >= base { return candidate }
        }
        return nil
    }

    private static func nextDayOfMonth(_ day: Int, from date: Date, calendar: Calendar) -> Date? {
        let base = calendar.startOfDay(for: date)
        let current = calendar.dateComponents([.year, .month], from: base)
        guard let currentMonth = calendar.date(from: DateComponents(year: current.year, month: current.month, day: 1)) else { return nil }

        for offset in 0..<24 {
            guard let month = calendar.date(byAdding: .month, value: offset, to: currentMonth) else { continue }
            let components = calendar.dateComponents([.year, .month], from: month)
            guard let candidate = calendar.date(from: DateComponents(year: components.year, month: components.month, day: day)),
                  calendar.component(.day, from: candidate) == day,
                  calendar.component(.month, from: candidate) == calendar.component(.month, from: month) else { continue }
            if candidate >= base { return candidate }
        }
        return nil
    }

    private static func applyingTime(_ token: String?, to date: Date, calendar: Calendar) -> (date: Date, hasTime: Bool) {
        guard let token, let time = parseTime(token),
              let datedTime = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: date) else {
            return (date, false)
        }
        return (datedTime, true)
    }

    private static func parseTime(_ token: String) -> (hour: Int, minute: Int)? {
        let value = token.trimmingCharacters(in: .whitespaces).lowercased()
        if value == "noon" {
            return (12, 0)
        }
        if value.hasSuffix("am") || value.hasSuffix("pm") {
            let suffix = String(value.suffix(2))
            let components = value.dropLast(2).trimmingCharacters(in: .whitespaces).split(separator: ":")
            guard components.count == 1 || components.count == 2,
                  let originalHour = Int(components[0]), (1...12).contains(originalHour),
                  let minute = components.count == 2 ? Int(components[1]) : 0, (0...59).contains(minute) else { return nil }
            return (suffix == "pm" ? (originalHour == 12 ? 12 : originalHour + 12) : (originalHour == 12 ? 0 : originalHour), minute)
        }
        if value.count == 4, let hour = Int(value.prefix(2)), let minute = Int(value.suffix(2)), (0...23).contains(hour), (0...59).contains(minute) {
            return (hour, minute)
        }
        let components = value.split(separator: ":")
        guard components.count == 2, let hour = Int(components[0]), let minute = Int(components[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }

    private static func fullWeekdayName(_ weekday: Int) -> String {
        ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][weekday]
    }

    private static func firstMatch(
        _ pattern: String,
        in text: String,
        excluding excludedRanges: [NSRange]
    ) -> NSTextCheckingResult? {
        let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        return expression?.matches(in: text, range: NSRange(text.startIndex..., in: text)).first { match in
            !excludedRanges.contains { NSIntersectionRange($0, match.range).length > 0 }
        }
    }

    private static func capture(_ index: Int, from match: NSTextCheckingResult, in text: String) -> String? {
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }

    private static func removing(_ range: NSRange, from text: String) -> String {
        guard let range = Range(range, in: text) else { return text }
        return text.replacingCharacters(in: range, with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
