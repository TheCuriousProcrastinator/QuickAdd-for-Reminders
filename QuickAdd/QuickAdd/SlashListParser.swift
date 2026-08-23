import Foundation
import EventKit

struct SlashListMatch {
    let listID: String
    let range: Range<String.Index>
}

struct SlashListFragment {
    let range: Range<String.Index>
    let query: String
}

enum SlashListParser {
    static func matchingList(in text: String, lists: [EKCalendar]) -> SlashListMatch? {
        var best: SlashListMatch?

        for list in lists where !list.title.isEmpty {
            let pattern = #"(^|\s)(/"# + NSRegularExpression.escapedPattern(for: list.title) + #")(?=$|\s|[.,!?;:])"#
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))

            for match in matches {
                let tokenRange = match.range(at: 2)
                guard let range = Range(tokenRange, in: text) else { continue }
                if best == nil || range.lowerBound > best!.range.lowerBound {
                    best = SlashListMatch(listID: list.calendarIdentifier, range: range)
                }
            }
        }

        return best
    }

    static func fragment(in text: String) -> SlashListFragment? {
        guard let slash = text.lastIndex(of: "/") else { return nil }
        guard slash == text.startIndex || text[text.index(before: slash)].isWhitespace else { return nil }

        let queryStart = text.index(after: slash)
        let query = String(text[queryStart...])
        guard !query.contains("/"), !query.contains("\n"), query.count <= 80 else { return nil }
        return SlashListFragment(range: slash..<text.endIndex, query: query)
    }

    static func suggestions(for fragment: SlashListFragment, lists: [EKCalendar]) -> [EKCalendar] {
        let query = fragment.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let starts = lists.filter {
            query.isEmpty || $0.title.range(of: query, options: [.caseInsensitive, .anchored]) != nil
        }
        let contains = lists.filter {
            !query.isEmpty && $0.title.range(of: query, options: [.caseInsensitive, .anchored]) == nil
                && $0.title.range(of: query, options: .caseInsensitive) != nil
        }
        let ordered: [EKCalendar] = starts + contains
        return Array(ordered.prefix(7))
    }

    static func replacing(_ fragment: SlashListFragment, in text: String, with listTitle: String) -> String {
        let after = text[fragment.range.upperBound...]
        let needsSpace = !after.isEmpty && !after.first!.isWhitespace
        return String(text[..<fragment.range.lowerBound]) + "/" + listTitle + (needsSpace ? " " : "") + after
    }

    static func removing(_ fragment: SlashListFragment, from text: String) -> String {
        text.replacingCharacters(in: fragment.range, with: "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func removingMatchedList(from text: String, lists: [EKCalendar]) -> String {
        guard let match = matchingList(in: text, lists: lists) else { return text }
        return text.replacingCharacters(in: match.range, with: "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
