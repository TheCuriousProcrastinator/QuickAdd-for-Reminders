import Foundation

// Run from the repository root:
// swiftc QuickAdd/QuickAdd/Natural{Date,Recurrence,Priority}Parser.swift Tests/NaturalDateParserRegression.swift -o /tmp/QuickAddDateTests
// /tmp/QuickAddDateTests
@main
struct NaturalDateParserRegression {
    static var checks = 0
    static var failures = 0
    static var calendar: Calendar = {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "America/New_York")!
        return result
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static func check(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { failures += 1; print("FAIL: \(message)") }
    }

    static func expect(_ phrase: String, _ expected: Date, timed: Bool = false, now: Date? = nil) {
        let text = "Task \(phrase)"
        let result = NaturalDateParser.parseResults(text, now: now ?? date(2026, 8, 31, 10), calendar: calendar)
        let base = result.date ?? result.time
        var actual = base?.date
        if let dateResult = result.date, let time = result.time {
            actual = calendar.date(bySettingHour: calendar.component(.hour, from: time.date), minute: calendar.component(.minute, from: time.date), second: 0, of: dateResult.date)
        }
        check(actual == expected, "\(phrase): date \(String(describing: actual)) != \(expected)")
        check((result.date?.hasTime == true || result.time != nil) == timed, "\(phrase): all-day/timed flag")
        let ranges = [result.date?.recognizedRange, result.time?.recognizedRange].compactMap { $0 }
        var cleaned = text
        for range in ranges.sorted(by: { $0.location > $1.location }) {
            cleaned = (cleaned as NSString).replacingCharacters(in: range, with: "")
        }
        check(cleaned.trimmingCharacters(in: .whitespaces) == "Task", "\(phrase): complete phrase cleanup, got \(cleaned)")
        for result in [result.date, result.time].compactMap({ $0 }) {
            check((text as NSString).substring(with: result.recognizedRange) == result.recognizedText, "\(phrase): highlight range")
        }
        // Excluding all recognized occurrences must leave them ordinary text, not re-parse fragments.
        let rejected = NaturalDateParser.parseResults(text, now: now ?? date(2026, 8, 31, 10), calendar: calendar, excluding: ranges)
        check(rejected.date == nil && rejected.time == nil && rejected.noDate == nil, "\(phrase): occurrence rejection")
    }

    static func main() {
        for (period, hour) in [("morning", 9), ("afternoon", 12), ("evening", 19), ("night", 22)] {
            for alias in ["tom", "tmr", "tomorrow"] {
                expect("\(alias) \(period)", date(2026, 9, 1, hour), timed: true)
            }
            expect("in the \(period)", date(2026, 8, hour <= 10 ? 32 : 31, hour), timed: true)
        }
        expect("next year", date(2027, 1, 1))
        expect("next   year", date(2027, 1, 1))
        for phrase in ["Jan 27", "27 Jan", "Jan 27 2027", "27 Jan 2027"] {
            expect(phrase, date(2027, 1, 27))
        }
        expect("27th", date(2026, 9, 27))
        expect("mid January", date(2027, 1, 15))
        expect("end of month", date(2026, 8, 31))
        expect("+5 days", date(2026, 9, 5))
        expect("+3 weeks", date(2026, 9, 21))
        expect("6pm", date(2026, 8, 31, 18), timed: true)
        expect("6pm", date(2026, 9, 1, 18), timed: true, now: date(2026, 8, 31, 19))
        expect("6pm", date(2026, 9, 1, 18), timed: true, now: date(2026, 8, 31, 18))
        expect("6 weeks before 21 Jul", date(2027, 6, 9))
        expect("28 days after 21 July", date(2027, 8, 18))
        expect("6 weeks before 21 Jul", date(2026, 6, 9), now: date(2026, 1, 1))
        expect("28 days after 21 July", date(2027, 8, 18), now: date(2026, 8, 1))
        expect("28 days after 21 July 2026", date(2026, 8, 18))
        expect("Jan 27 2027 at 3pm", date(2027, 1, 27, 15), timed: true)
        expect("27 Jan morning", date(2027, 1, 27, 9), timed: true)
        expect("mid January evening", date(2027, 1, 15, 19), timed: true)
        expect("27th at noon", date(2026, 9, 27, 12), timed: true)
        expect("6 weeks before 21 Jul at 15:00", date(2027, 6, 9, 15), timed: true)
        expect("end of month", date(2028, 2, 29), now: date(2028, 2, 5))
        expect("end of month", date(2027, 2, 28), now: date(2027, 2, 5))
        expect("Feb 29", date(2028, 2, 29))
        expect("Jan 27 2025", date(2025, 1, 27))
        expect("Jan 27", date(2027, 1, 27), now: date(2027, 1, 27, 20))
        expect("tom morning", date(2027, 1, 1, 9), timed: true, now: date(2026, 12, 31, 23))
        expect("next year", date(2027, 1, 1), now: date(2026, 12, 31))
        // Calendar arithmetic across the spring DST transition (a 23-hour day).
        expect("+5 days", date(2027, 3, 17), now: date(2027, 3, 12, 15))
        expect("+3 weeks", date(2027, 4, 2), now: date(2027, 3, 12, 15))
        expect("6pm", date(2027, 3, 14, 18), timed: true, now: date(2027, 3, 13, 19))
        for phrase in ["Buy 3 apples", "Read 3 Body Problem", "Call room 204", "morning meeting", "night shift", "Feb 30", "Feb 29 2027", "Apr 31 2027", "23th", "32nd", "x+5 days"] {
            let result = NaturalDateParser.parseResults(phrase, now: date(2026, 8, 31, 10), calendar: calendar)
            check(result.date == nil && result.time == nil, "conservative: \(phrase)")
        }
        expect("31st", date(2026, 5, 31), now: date(2026, 4, 1))
        // Existing aliases, ordinal weekdays, times, and relative dates.
        expect("tod at 3pm", date(2026, 8, 31, 15), timed: true)
        expect("today at 6pm", date(2026, 8, 31, 18), timed: true, now: date(2026, 8, 31, 20))
        expect("tom 9:30", date(2026, 9, 1, 9, 30), timed: true)
        expect("tomorrow at noon", date(2026, 9, 1, 12), timed: true)
        expect("at 15:00", date(2026, 8, 31, 15), timed: true)
        expect("in 4 weeks", date(2026, 9, 28))
        expect("in a month", date(2026, 9, 30))
        expect("in 2 hours", date(2026, 8, 31, 12), timed: true)
        expect("last saturday of september", date(2026, 9, 26))

        let mixed = "Call John tod /Work p1 about budget at 3pm"
        let priority = NaturalPriorityParser.parse(mixed)!
        let listRange = (mixed as NSString).range(of: "/Work")
        let mixedResults = NaturalDateParser.parseResults(mixed, now: date(2026, 8, 31, 10), calendar: calendar, excluding: [priority.recognizedRange, listRange])
        check(mixedResults.date?.recognizedText == "tod" && mixedResults.time?.recognizedText == "at 3pm", "independent metadata ranges")
        check(priority.value == 1, "priority unchanged")
        let recurrenceText = "every first mon p1 at noon"
        let recurrence = NaturalRecurrenceParser.parse(recurrenceText, now: date(2026, 8, 31, 10), calendar: calendar)!
        let recurrenceTime = NaturalDateParser.parseResults(recurrenceText, now: date(2026, 8, 31, 10), calendar: calendar, excluding: [recurrence.recognizedRange]).time
        check(recurrence.recurrence.weekdays.first?.weekNumber == 1 && recurrenceTime?.recognizedText == "at noon", "recurrence unchanged")

        let rejectedText = "tom morning tomorrow in the evening"
        let first = NaturalDateParser.parseResults(rejectedText, now: date(2026, 8, 31, 10), calendar: calendar).date!
        let next = NaturalDateParser.parseResults(rejectedText, now: date(2026, 8, 31, 10), calendar: calendar, excluding: [first.recognizedRange])
        check(next.date?.recognizedText == "tomorrow in the evening", "continue after rejected occurrence")
        let rejectedCalendarText = "Jan 27 2027 and Feb 28 2027"
        let rejectedCalendar = NaturalDateParser.parseResults(rejectedCalendarText, now: date(2026, 8, 31), calendar: calendar, excluding: [(rejectedCalendarText as NSString).range(of: "Jan 27 2027")])
        check(rejectedCalendar.date?.recognizedText == "Feb 28 2027", "continue after rejected calendar date")
        extendedGrammarChecks()
        print("\(checks - failures)/\(checks) checks passed")
        if failures > 0 { exit(1) }
    }

    static func extendedGrammarChecks() {
        let months = [
            ["Jan", "January"], ["Feb", "February"], ["Mar", "March"], ["Apr", "April"],
            ["May"], ["Jun", "June"], ["Jul", "July"], ["Aug", "August"],
            ["Sep", "Sept", "September"], ["Oct", "October"], ["Nov", "November"], ["Dec", "December"]
        ]
        for (index, aliases) in months.enumerated() {
            let month = index + 1
            for alias in aliases {
                for phrase in ["\(alias) 27", "27 \(alias)"] {
                    expect(phrase, date(2027, month, 27), now: date(2027, 1, 1))
                }
                for phrase in ["\(alias) 27 2027", "\(alias) 27, 2027", "27 \(alias) 2027"] {
                    expect(phrase, date(2027, month, 27))
                }
                expect("mid \(alias)", date(2027, month, 15), now: date(2027, 1, 1))
            }
        }
        for day in 1...31 {
            let suffix = (11...13).contains(day) ? "th" : [1: "st", 2: "nd", 3: "rd"][day % 10] ?? "th"
            expect("\(day)\(suffix)", date(2026, 8, day), now: date(2026, 8, 1))
        }
        expect("27th", date(2026, 8, 27), now: date(2026, 8, 27, 20))
        expect("31st", date(2026, 3, 31), now: date(2026, 2, 1))
        expect("29th", date(2027, 3, 29), now: date(2027, 2, 1))
        expect("29th", date(2028, 2, 29), now: date(2028, 2, 1))
        expect("1st", date(2027, 1, 1), now: date(2026, 12, 31))
        expect("end of month at 4pm", date(2026, 8, 31, 16), timed: true)
        expect("+2 months", date(2026, 10, 31))
        expect("+1 month", date(2026, 9, 30))
        expect("+1 month", date(2027, 2, 28), now: date(2027, 1, 31))
        expect("+1 month", date(2028, 2, 29), now: date(2028, 1, 31))
        expect("in a month", date(2028, 2, 29), now: date(2028, 1, 31))
        expect("5 days before Jan 27", date(2027, 1, 22))
        expect("2 weeks after September 3", date(2026, 9, 17))
        expect("1 month after Jan 31 2027", date(2027, 2, 28))
        expect("1 month after Jan 31 2028", date(2028, 2, 29))
        expect("2 months before 31 March 2027", date(2027, 1, 31))
        expect("1 month before March 31 2027", date(2027, 2, 28))
        expect("6 weeks before 21 Jul", date(2026, 6, 9), now: date(2026, 7, 1))
        expect("6 weeks before 21 Jul", date(2027, 6, 9), now: date(2026, 7, 22))
        expect("noon", date(2026, 8, 31, 12), timed: true)
        for (phrase, hour, minute) in [("4pm", 16, 0), ("4:30pm", 16, 30), ("16:00", 16, 0), ("1600", 16, 0), ("noon", 12, 0), ("morning", 9, 0), ("afternoon", 12, 0), ("evening", 19, 0)] {
            expect(phrase, date(2026, 8, 31, hour, minute), timed: true, now: date(2026, 8, 31, 8))
            expect(phrase, date(2026, 9, 1, hour, minute), timed: true, now: date(2026, 8, 31, 23))
            expect("today \(phrase)", date(2026, 8, 31, hour, minute), timed: true, now: date(2026, 8, 31, 23))
        }
        for text in ["Meet Tom Hanks", "Call TOM", "midnight", "01/02/2027", "27/1", "2027-01-02", "discuss date format", "no dates", "no due dates", "node date"] {
            let result = NaturalDateParser.parseResults(text, now: date(2026, 8, 31, 10), calendar: calendar)
            check(result.date == nil && result.time == nil && result.noDate == nil, "unchanged ordinary/unsupported text: \(text)")
        }
        for phrase in ["no date", "no due date", "NO DUE DATE", "no   date"] {
            let text = "Read \(phrase)"
            let result = NaturalDateParser.parseResults(text, now: date(2026, 8, 31), calendar: calendar)
            check(result.date == nil && result.time == nil, "no-date has no phantom date/time")
            check(result.noDate?.recognizedText == phrase && result.noDate?.title == "Read", "no-date title/recognition")
            check(result.noDate?.recognizedRange == (text as NSString).range(of: phrase), "no-date source range")
            let excluded = NaturalDateParser.parseResults(text, calendar: calendar, excluding: [(text as NSString).range(of: phrase)])
            check(excluded.noDate == nil, "no-date rejection")
        }
        let conflict = NaturalDateParser.parseResults("Read tomorrow no date at 3pm", calendar: calendar)
        check(conflict.noDate != nil && conflict.date == nil && conflict.time == nil, "explicit no-date clears automatic metadata")
        let rejectedClear = NaturalDateParser.parseResults("Read tomorrow no date", now: date(2026, 8, 31), calendar: calendar, excluding: [NSRange(location: 14, length: 7)])
        check(rejectedClear.date?.recognizedText == "tomorrow", "rejecting no-date restores other eligible recognition")
        let repeatedClear = NaturalDateParser.parseResults("no date no due date", excluding: [NSRange(location: 0, length: 7)])
        check(repeatedClear.noDate?.recognizedText == "no due date", "no-date rejection is occurrence-specific")
        expect("tomorrow", date(2026, 9, 1))
        expect("tmr", date(2026, 9, 1))
        let tom = NaturalDateParser.parseResults("Meet tom today", now: date(2026, 8, 31), calendar: calendar)
        check(tom.date?.recognizedText == "tom", "lowercase tom retains existing precedence")
        expect("Friday", date(2026, 9, 4))
        expect("next Monday", date(2026, 9, 7))
        expect("Friday 3pm", date(2026, 9, 4, 15), timed: true)
        expect("at 16:00", date(2026, 8, 31, 16), timed: true)
        expect("in 20 minutes", date(2026, 8, 31, 10, 20), timed: true)
        expect("in a week at noon", date(2026, 9, 7, 12), timed: true)
        expect("next weekend", date(2026, 9, 12))
        expect("next month", date(2026, 9, 30))
        expect("3rd Friday of September", date(2026, 9, 18))
        expect("last Friday of Nov", date(2026, 11, 27))
        for phrase in ["every weekday at 9am", "every weekend", "ev mon, wed, fri 3pm", "every 3rd Friday", "every other Monday", "every 3 days", "every other month", "quarterly", "every 27th", "ev   27th"] {
            let text = "Do this \(phrase)"
            guard let recurrence = NaturalRecurrenceParser.parse(text, now: date(2026, 8, 31), calendar: calendar) else {
                check(false, "recurrence: \(phrase)"); continue
            }
            check(recurrence.recognizedText == phrase, "recurrence owns entire phrase: \(phrase)")
            // Same recurrence-first routing/exclusion used by ContentView.
            let oneTime = NaturalDateParser.parseResults(text, now: date(2026, 8, 31), calendar: calendar, excluding: [recurrence.recognizedRange])
            check(oneTime.date == nil && oneTime.time == nil, "one-time parser respects recurrence exclusion: \(phrase)")
        }
        let bareRecurrence = NaturalDateParser.parseResults("Do this every 27th", calendar: calendar)
        check(bareRecurrence.date == nil, "bare ordinal does not steal every 27th")
        let precedence = NaturalDateParser.parseResults("last Friday of Nov 5 days before Jan 27", now: date(2026, 8, 31), calendar: calendar)
        check(precedence.date?.recognizedText == "5 days before Jan 27", "relative offsets before special named dates")
    }
}
