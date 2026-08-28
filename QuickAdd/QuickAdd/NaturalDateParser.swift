import Foundation

struct NaturalDateParseResult {
    let title: String
    let date: Date
    let hasTime: Bool
    let recognizedRange: NSRange
    let recognizedText: String
}

struct NaturalDateParseResults {
    let date: NaturalDateParseResult?
    let time: NaturalDateParseResult?
}

enum NaturalDateParser {
    private static let weekdays: [String: Int] = [
        "sunday": 1, "sun": 1, "monday": 2, "mon": 2,
        "tuesday": 3, "tue": 3, "tues": 3, "wednesday": 4, "wed": 4,
        "thursday": 5, "thu": 5, "thur": 5, "thurs": 5,
        "friday": 6, "fri": 6, "saturday": 7, "sat": 7
    ]

    private static let weekdayPattern = "sunday|sun|monday|mon|tuesday|tue|tues|wednesday|wed|thursday|thu|thur|thurs|friday|fri|saturday|sat"
    private static let ordinals: [String: Int] = [
        "1st": 1, "first": 1, "2nd": 2, "second": 2,
        "3rd": 3, "third": 3, "4th": 4, "fourth": 4,
        "5th": 5, "fifth": 5, "last": -1
    ]
    private static let ordinalPattern = "1st|first|2nd|second|3rd|third|4th|fourth|5th|fifth|last"
    private static let months: [String: Int] = [
        "january": 1, "jan": 1, "february": 2, "feb": 2,
        "march": 3, "mar": 3, "april": 4, "apr": 4,
        "may": 5, "june": 6, "jun": 6, "july": 7, "jul": 7,
        "august": 8, "aug": 8, "september": 9, "sept": 9, "sep": 9,
        "october": 10, "oct": 10, "november": 11, "nov": 11,
        "december": 12, "dec": 12
    ]
    private static let monthPattern = "january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sept|sep|october|oct|november|nov|december|dec"
    private static let timePattern = #"(?:noon|\d{1,2}(?::\d{2})?\s*(?:am|pm)|(?:[01]?\d|2[0-3]):[0-5]\d|(?:[01]\d|2[0-3])[0-5]\d)"#

    static func parseResults(
        _ text: String,
        now: Date = Date(),
        calendar: Calendar = .current,
        excluding excludedRanges: [NSRange] = []
    ) -> NaturalDateParseResults {
        let date = parseRelative(text, now: now, calendar: calendar, excluding: excludedRanges)
            ?? parseNamedDate(text, now: now, calendar: calendar, excluding: excludedRanges)
        let timeExclusions = excludedRanges + (date.map { [$0.recognizedRange] } ?? [])
        let time = date?.hasTime == true
            ? nil
            : parseTimeOnly(text, now: now, calendar: calendar, excluding: timeExclusions)
        return NaturalDateParseResults(date: date, time: time)
    }

    private static func parseRelative(
        _ text: String,
        now: Date,
        calendar: Calendar,
        excluding excludedRanges: [NSRange]
    ) -> NaturalDateParseResult? {
        let pattern = #"\bin\s+(?:(a)|(\d+))\s+(minutes?|mins?|hours?|hrs?|days?|weeks?|months?)(?:\s+(?:at\s+)?("# + timePattern + #"))?\b"#
        guard let match = firstMatch(pattern, in: text, excluding: excludedRanges),
              let unit = capture(3, from: match, in: text)?.lowercased() else { return nil }

        let amount = capture(1, from: match, in: text) == "a" ? 1 : Int(capture(2, from: match, in: text) ?? "")
        guard let amount, amount > 0 else { return nil }

        let time = capture(4, from: match, in: text).flatMap(parseTime)
        let isTimedUnit = unit.hasPrefix("min") || unit.hasPrefix("hour") || unit.hasPrefix("hr")
        let base: Date
        if unit.hasPrefix("min") {
            base = calendar.date(byAdding: .minute, value: amount, to: now) ?? now
        } else if unit.hasPrefix("hour") || unit.hasPrefix("hr") {
            base = calendar.date(byAdding: .hour, value: amount, to: now) ?? now
        } else if unit.hasPrefix("day") {
            base = calendar.date(byAdding: .day, value: amount, to: calendar.startOfDay(for: now)) ?? now
        } else if unit.hasPrefix("week") {
            base = calendar.date(byAdding: .weekOfYear, value: amount, to: calendar.startOfDay(for: now)) ?? now
        } else {
            base = calendar.date(byAdding: .month, value: amount, to: calendar.startOfDay(for: now)) ?? now
        }

        let date = time.flatMap {
            calendar.date(bySettingHour: $0.hour, minute: $0.minute, second: 0, of: base)
        } ?? base
        return result(for: match, in: text, date: date, hasTime: isTimedUnit || time != nil)
    }

    private static func parseNamedDate(
        _ text: String,
        now: Date,
        calendar: Calendar,
        excluding excludedRanges: [NSRange]
    ) -> NaturalDateParseResult? {
        let ordinalWeekdayPattern = #"\b(?:(?:on\s+)?the\s+|on\s+)?("#
            + ordinalPattern + #")\s+("# + weekdayPattern
            + #")\s+(?:of|in)\s+("# + monthPattern
            + #")(?:\s*,?\s*(\d{4}))?(?:\s+(?:at\s+)?("# + timePattern + #"))?\b"#
        if let match = firstMatch(ordinalWeekdayPattern, in: text, excluding: excludedRanges) {
            guard
                let ordinalToken = capture(1, from: match, in: text)?.lowercased(),
                let weekNumber = ordinals[ordinalToken],
                let weekdayToken = capture(2, from: match, in: text)?.lowercased(),
                let weekday = weekdays[weekdayToken],
                let monthToken = capture(3, from: match, in: text)?.lowercased(),
                let month = months[monthToken],
                let date = resolveOrdinalWeekdayOfMonth(
                    weekday: weekday,
                    weekNumber: weekNumber,
                    month: month,
                    year: capture(4, from: match, in: text).flatMap(Int.init),
                    now: now,
                    calendar: calendar
                )
            else {
                return nil
            }

            return result(
                for: match,
                in: text,
                date: applyingTime(capture(5, from: match, in: text), to: date, calendar: calendar)
            )
        }

        let specialPattern = #"\b(next\s+weekend|(?:this\s+)?weekend|next\s+week|next\s+month)(?:\s+(?:at\s+)?("# + timePattern + #"))?\b"#
        if let match = firstMatch(specialPattern, in: text, excluding: excludedRanges),
           let token = capture(1, from: match, in: text),
           let date = resolveSpecialDate(token, now: now, calendar: calendar) {
            return result(for: match, in: text, date: applyingTime(capture(2, from: match, in: text), to: date, calendar: calendar))
        }

        let nextWeekdayPattern = #"\bnext\s+("# + weekdayPattern + #")(?:\s+(?:at\s+)?("# + timePattern + #"))?\b"#
        if let match = firstMatch(nextWeekdayPattern, in: text, excluding: excludedRanges),
           let token = capture(1, from: match, in: text),
           let date = resolveWeekday(token, now: now, calendar: calendar, allowToday: false) {
            return result(for: match, in: text, date: applyingTime(capture(2, from: match, in: text), to: date, calendar: calendar))
        }

        // Keep the short "tom" alias conservative so a capitalized person's name
        // such as "Tom Hanks" is not interpreted as Tomorrow.
        let datePattern = "today|(?-i:tod)|tomorrow|(?-i:tom|tmr)|tonight|\(weekdayPattern)"
        let pattern = #"\b("# + datePattern + #")(?:\s+(?:at\s+)?("# + timePattern + #"))?\b"#
        if let match = firstMatch(pattern, in: text, excluding: excludedRanges),
           let token = capture(1, from: match, in: text),
           let date = resolveDate(token, now: now, calendar: calendar) {
            return result(for: match, in: text, date: applyingTime(capture(2, from: match, in: text), to: date, calendar: calendar))
        }
        return nil
    }

    private static func parseTimeOnly(
        _ text: String,
        now: Date,
        calendar: Calendar,
        excluding excludedRanges: [NSRange]
    ) -> NaturalDateParseResult? {
        let explicitPattern = #"\bat\s+("# + timePattern + #")\b"#
        let terminalPattern = #"\b("# + timePattern + #")\s*$"#
        let match = firstMatch(explicitPattern, in: text, excluding: excludedRanges)
            ?? firstMatch(terminalPattern, in: text, excluding: excludedRanges)
        guard let match,
              let token = capture(1, from: match, in: text),
              let time = parseTime(token),
              let date = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: now) else { return nil }
        return result(for: match, in: text, date: date, hasTime: true)
    }

    private static func resolveSpecialDate(_ token: String, now: Date, calendar: Calendar) -> Date? {
        let day = calendar.startOfDay(for: now)
        switch token.lowercased() {
        case "weekend", "this weekend":
            return nextWeekday(7, from: day, calendar: calendar, allowToday: true)
        case "next weekend":
            guard let saturday = nextWeekday(7, from: day, calendar: calendar, allowToday: false) else { return nil }
            return calendar.date(byAdding: .day, value: 7, to: saturday)
        case "next week":
            return nextWeekday(2, from: day, calendar: calendar, allowToday: false)
        case "next month":
            return calendar.date(byAdding: .month, value: 1, to: day)
        default:
            return nil
        }
    }

    private static func resolveDate(_ token: String, now: Date, calendar: Calendar) -> Date? {
        let day = calendar.startOfDay(for: now)
        switch token.lowercased() {
        case "today", "tod", "tonight":
            return day
        case "tomorrow", "tom", "tmr":
            return calendar.date(byAdding: .day, value: 1, to: day)
        default:
            return resolveWeekday(token, now: now, calendar: calendar, allowToday: true)
        }
    }

    private static func resolveWeekday(_ token: String, now: Date, calendar: Calendar, allowToday: Bool) -> Date? {
        guard let weekday = weekdays[token.lowercased()] else { return nil }
        return nextWeekday(weekday, from: calendar.startOfDay(for: now), calendar: calendar, allowToday: allowToday)
    }

    private static func nextWeekday(_ weekday: Int, from date: Date, calendar: Calendar, allowToday: Bool) -> Date? {
        let current = calendar.component(.weekday, from: date)
        var offset = (weekday - current + 7) % 7
        if offset == 0 && !allowToday { offset = 7 }
        return calendar.date(byAdding: .day, value: offset, to: date)
    }

    private static func resolveOrdinalWeekdayOfMonth(
        weekday: Int,
        weekNumber: Int,
        month: Int,
        year: Int?,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let today = calendar.startOfDay(for: now)
        let currentYear = calendar.component(.year, from: today)

        if let year {
            return ordinalWeekdayDate(
                weekday: weekday,
                weekNumber: weekNumber,
                month: month,
                year: year,
                calendar: calendar
            )
        }

        for candidateYear in currentYear...(currentYear + 20) {
            if let candidate = ordinalWeekdayDate(
                weekday: weekday,
                weekNumber: weekNumber,
                month: month,
                year: candidateYear,
                calendar: calendar
            ), candidate >= today {
                return candidate
            }
        }
        return nil
    }

    private static func ordinalWeekdayDate(
        weekday: Int,
        weekNumber: Int,
        month: Int,
        year: Int,
        calendar: Calendar
    ) -> Date? {
        guard let monthStart = calendar.date(
            from: DateComponents(year: year, month: month, day: 1)
        ) else {
            return nil
        }

        let candidate: Date?
        if weekNumber == -1 {
            guard
                let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart),
                let lastDay = calendar.date(byAdding: .day, value: -1, to: nextMonth)
            else {
                return nil
            }
            let offset = (calendar.component(.weekday, from: lastDay) - weekday + 7) % 7
            candidate = calendar.date(byAdding: .day, value: -offset, to: lastDay)
        } else {
            let firstWeekday = calendar.component(.weekday, from: monthStart)
            let day = 1 + (weekday - firstWeekday + 7) % 7 + (weekNumber - 1) * 7
            candidate = calendar.date(
                from: DateComponents(year: year, month: month, day: day)
            )
        }

        guard
            let candidate,
            calendar.component(.year, from: candidate) == year,
            calendar.component(.month, from: candidate) == month
        else {
            return nil
        }
        return calendar.startOfDay(for: candidate)
    }

    private static func applyingTime(_ token: String?, to date: Date, calendar: Calendar) -> (date: Date, hasTime: Bool) {
        guard let token, let time = parseTime(token),
              let datedTime = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: date) else {
            return (date, false)
        }
        return (datedTime, true)
    }

    private static func result(for match: NSTextCheckingResult, in text: String, date: Date, hasTime: Bool = false) -> NaturalDateParseResult {
        NaturalDateParseResult(
            title: removing(match.range, from: text),
            date: date,
            hasTime: hasTime,
            recognizedRange: match.range,
            recognizedText: (text as NSString).substring(with: match.range)
        )
    }

    private static func result(for match: NSTextCheckingResult, in text: String, date: (date: Date, hasTime: Bool)) -> NaturalDateParseResult {
        result(for: match, in: text, date: date.date, hasTime: date.hasTime)
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

    private static func firstMatch(
        _ pattern: String,
        in text: String,
        excluding excludedRanges: [NSRange]
    ) -> NSTextCheckingResult? {
        let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        return expression?.matches(in: text, range: NSRange(text.startIndex..., in: text)).first { match in
            !excludedRanges.contains {
                NSIntersectionRange($0, match.range).length > 0
            }
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
