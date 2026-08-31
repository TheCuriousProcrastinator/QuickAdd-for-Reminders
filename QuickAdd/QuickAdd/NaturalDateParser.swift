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
    let noDate: NaturalNoDateParseResult?
}

// An explicit clearing instruction, not a missing parse or an invented sentinel date.
struct NaturalNoDateParseResult {
    let title: String
    let recognizedRange: NSRange
    let recognizedText: String
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
    private static let numericTimePattern = #"(?:noon|\d{1,2}(?::\d{2})?\s*(?:am|pm)|(?:[01]?\d|2[0-3]):[0-5]\d|(?:[01]\d|2[0-3])[0-5]\d)"#
    private static let dayPeriodPattern = "morning|afternoon|evening|night"
    private static let timePattern = "(?:\(numericTimePattern)|(?:in\\s+the\\s+)?(?:\(dayPeriodPattern)))"
    private static let calendarOffsetPattern = #"(\d+)\s+(days?|weeks?|months?)\s+(before|after)\s+"#
    private static let monthDayPattern = #"(?:("#
        + monthPattern + #")\s+(\d{1,2})|(\d{1,2})\s+("# + monthPattern
        + #"))(?:(?:\s*,\s*|\s+)(\d{4}))?\b"#
    private static let calendarDatePattern = #"\b(?:"# + calendarOffsetPattern + #")?"# + monthDayPattern

    static func parseResults(
        _ text: String,
        now: Date = Date(),
        calendar: Calendar = .current,
        excluding excludedRanges: [NSRange] = []
    ) -> NaturalDateParseResults {
        if let match = firstMatch(#"\bno\s+(?:due\s+)?date\b"#, in: text, excluding: excludedRanges) {
            return NaturalDateParseResults(date: nil, time: nil, noDate: NaturalNoDateParseResult(
                title: removing(match.range, from: text),
                recognizedRange: match.range,
                recognizedText: (text as NSString).substring(with: match.range)
            ))
        }
        let date = parseRelative(text, now: now, calendar: calendar, excluding: excludedRanges)
            ?? parseCalendarDate(text, now: now, calendar: calendar, excluding: excludedRanges, offsetsOnly: true)
            ?? parseNamedDate(text, now: now, calendar: calendar, excluding: excludedRanges)
        // A year inside a rejected/invalid calendar date must not become a compact time.
        let calendarRanges = matches(calendarDatePattern, in: text, excluding: []).map(\.range)
        let numericDateRanges = matches(#"\b\d{1,4}[-/]\d{1,2}(?:[-/]\d{1,4})?\b"#, in: text, excluding: []).map(\.range)
        let timeExclusions = excludedRanges + calendarRanges + numericDateRanges + (date.map { [$0.recognizedRange] } ?? [])
        let time = date?.hasTime == true
            ? nil
            : parseTimeOnly(text, now: now, calendar: calendar, rollForward: date == nil, excluding: timeExclusions)
        return NaturalDateParseResults(date: date, time: time, noDate: nil)
    }

    private static func parseRelative(
        _ text: String,
        now: Date,
        calendar: Calendar,
        excluding excludedRanges: [NSRange]
    ) -> NaturalDateParseResult? {
        let pattern = #"(?:\bin\s+(?:(a)|(\d+))|(?<![\w+])\+(\d+))\s+(minutes?|mins?|hours?|hrs?|days?|weeks?|months?)(?:\s+(?:at\s+)?("# + timePattern + #"))?\b"#
        guard let match = firstMatch(pattern, in: text, excluding: excludedRanges),
              let unit = capture(4, from: match, in: text)?.lowercased() else { return nil }

        let amount = capture(1, from: match, in: text)?.lowercased() == "a" ? 1
            : Int(capture(2, from: match, in: text) ?? capture(3, from: match, in: text) ?? "")
        guard let amount, amount > 0 else { return nil }

        let time = capture(5, from: match, in: text).flatMap { parseTime($0) }
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

        if let result = parseCalendarDate(text, now: now, calendar: calendar, excluding: excludedRanges) {
            return result
        }

        let specialPattern = #"\b(next\s+weekend|(?:this\s+)?weekend|next\s+week|next\s+month|next\s+year|end\s+of\s+month)(?:\s+(?:at\s+)?("# + timePattern + #"))?\b"#
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

    private static func parseCalendarDate(
        _ text: String,
        now: Date,
        calendar: Calendar,
        excluding excludedRanges: [NSRange],
        offsetsOnly: Bool = false
    ) -> NaturalDateParseResult? {
        let timedSuffix = #"(?:\s+(?:at\s+)?("# + timePattern + #")\b)?"#
        // Require the offset prefix on the high-precedence pass so earlier dates
        // cannot consume its amount (e.g. "Nov 5 days before Jan 27").
        let pattern = offsetsOnly ? #"\b"# + calendarOffsetPattern + monthDayPattern : calendarDatePattern
        for match in matches(pattern + timedSuffix, in: text, excluding: excludedRanges) {
            guard let monthToken = capture(4, from: match, in: text) ?? capture(7, from: match, in: text),
                  let month = months[monthToken.lowercased()],
                  let day = Int(capture(5, from: match, in: text) ?? capture(6, from: match, in: text) ?? "") else { continue }
            var offset = 0
            if let amount = capture(1, from: match, in: text) {
                guard let number = Int(amount), number > 0 else { continue }
                offset = capture(3, from: match, in: text)?.lowercased() == "before" ? -number : number
            }
            let unitToken = capture(2, from: match, in: text)?.lowercased() ?? "day"
            let unit: Calendar.Component = unitToken.hasPrefix("month") ? .month : (unitToken.hasPrefix("week") ? .weekOfYear : .day)
            guard let date = resolveMonthDay(
                day: day, month: month, year: capture(8, from: match, in: text).flatMap(Int.init),
                offset: offset, unit: unit, now: now, calendar: calendar
            ) else { continue }
            return result(for: match, in: text, date: applyingTime(capture(9, from: match, in: text), to: date, calendar: calendar))
        }
        if offsetsOnly { return nil }

        let midPattern = #"\bmid\s+("# + monthPattern + #")\b"# + timedSuffix
        for match in matches(midPattern, in: text, excluding: excludedRanges) {
            guard let token = capture(1, from: match, in: text)?.lowercased(), let month = months[token],
                  let date = resolveMonthDay(day: 15, month: month, year: nil, now: now, calendar: calendar) else { continue }
            return result(for: match, in: text, date: applyingTime(capture(2, from: match, in: text), to: date, calendar: calendar))
        }

        // A passed or unavailable ordinal advances to the next month containing that day.
        let ordinalDayPattern = #"\b(1st|2nd|3rd|[4-9]th|1[0-9]th|20th|21st|22nd|23rd|2[4-9]th|30th|31st)\b"# + timedSuffix
        for match in matches(ordinalDayPattern, in: text, excluding: excludedRanges) {
            let prefix = (text as NSString).substring(to: match.range.location)
            guard prefix.range(of: #"\b(?:every|ev)\s+$"#, options: [.regularExpression, .caseInsensitive]) == nil else { continue }
            guard let token = capture(1, from: match, in: text), let day = Int(token.dropLast(2)),
                  let date = nextOrdinalDay(day, now: now, calendar: calendar) else { continue }
            return result(for: match, in: text, date: applyingTime(capture(2, from: match, in: text), to: date, calendar: calendar))
        }
        return nil
    }

    private static func nextOrdinalDay(_ day: Int, now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        guard let monthStart = calendar.dateInterval(of: .month, for: today)?.start else { return nil }
        for offset in 0...12 {
            guard let month = calendar.date(byAdding: .month, value: offset, to: monthStart),
                  let date = strictDate(year: calendar.component(.year, from: month), month: calendar.component(.month, from: month), day: day, calendar: calendar),
                  date >= today else { continue }
            return date
        }
        return nil
    }

    private static func strictDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else { return nil }
        return date
    }

    private static func resolveMonthDay(
        day: Int, month: Int, year: Int?, offset: Int = 0, unit: Calendar.Component = .day,
        now: Date, calendar: Calendar
    ) -> Date? {
        let today = calendar.startOfDay(for: now)
        // Resolve the next base date first, then apply the requested calendar offset.
        // A "before" result may therefore be in the past; do not silently change its year.
        let startYear = year ?? calendar.component(.year, from: today)
        guard (1...9999).contains(startYear) else { return nil }
        let endYear = year ?? min(startYear + 8, 9999) // Includes the next leap day.
        for candidateYear in startYear...endYear {
            guard let anchor = strictDate(year: candidateYear, month: month, day: day, calendar: calendar),
                  year != nil || anchor >= today else { continue }
            return calendar.date(byAdding: unit, value: offset, to: anchor)
        }
        return nil
    }

    private static func parseTimeOnly(
        _ text: String,
        now: Date,
        calendar: Calendar,
        rollForward: Bool,
        excluding excludedRanges: [NSRange]
    ) -> NaturalDateParseResult? {
        let explicitPattern = #"\bat\s+("# + timePattern + #")\b"#
        let periodPattern = #"\bin\s+the\s+("# + dayPeriodPattern + #")\b"#
        let terminalPattern = #"\b("# + numericTimePattern + "|" + dayPeriodPattern + #")\s*$"#
        let match = firstMatch(explicitPattern, in: text, excluding: excludedRanges)
            ?? firstMatch(periodPattern, in: text, excluding: excludedRanges)
            ?? firstMatch(terminalPattern, in: text, excluding: excludedRanges)
        guard let match,
              let token = capture(1, from: match, in: text),
              let time = parseTime(token),
              var date = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: now) else { return nil }
        if rollForward && date <= now {
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
                  let nextTime = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: tomorrow) else { return nil }
            date = nextTime
        }
        return result(for: match, in: text, date: date, hasTime: true)
    }

    private static func resolveSpecialDate(_ token: String, now: Date, calendar: Calendar) -> Date? {
        let day = calendar.startOfDay(for: now)
        switch token.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ") {
        case "weekend", "this weekend":
            return nextWeekday(7, from: day, calendar: calendar, allowToday: true)
        case "next weekend":
            guard let saturday = nextWeekday(7, from: day, calendar: calendar, allowToday: false) else { return nil }
            return calendar.date(byAdding: .day, value: 7, to: saturday)
        case "next week":
            return nextWeekday(2, from: day, calendar: calendar, allowToday: false)
        case "next month":
            return calendar.date(byAdding: .month, value: 1, to: day)
        case "next year":
            return calendar.date(from: DateComponents(year: calendar.component(.year, from: day) + 1, month: 1, day: 1))
        case "end of month":
            guard let interval = calendar.dateInterval(of: .month, for: day) else { return nil }
            return calendar.date(byAdding: .day, value: -1, to: interval.end)
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
        let value = token.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        switch value {
        case "morning", "in the morning": return (9, 0)
        case "noon", "afternoon", "in the afternoon": return (12, 0)
        case "evening", "in the evening": return (19, 0)
        case "night", "in the night": return (22, 0)
        default: break
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
        matches(pattern, in: text, excluding: excludedRanges).first
    }

    private static func matches(_ pattern: String, in text: String, excluding excludedRanges: [NSRange]) -> [NSTextCheckingResult] {
        let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        return expression?.matches(in: text, range: NSRange(text.startIndex..., in: text)).filter { match in
            !excludedRanges.contains {
                NSIntersectionRange($0, match.range).length > 0
            }
        } ?? []
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
