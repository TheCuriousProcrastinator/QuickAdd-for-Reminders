import Foundation

struct NaturalPriorityParseResult {
    let title: String
    let value: Int
    let label: String
    let recognizedRange: NSRange
    let recognizedText: String
}

enum NaturalPriorityParser {
    private static let priorities: [String: (value: Int, label: String)] = [
        "p1": (1, "High"),
        "p2": (5, "Medium"),
        "p3": (9, "Low"),
        "p4": (0, "None")
    ]

    static func parse(
        _ text: String,
        excluding excludedRanges: [NSRange] = []
    ) -> NaturalPriorityParseResult? {
        let pattern = #"(^|\s)(p[1-4])(?=$|\s|[.,!?;:])"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        var result: NaturalPriorityParseResult?
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let tokenRange = match.range(at: 2)
            guard !excludedRanges.contains(where: { NSIntersectionRange($0, tokenRange).length > 0 }) else {
                continue
            }
            let token = (text as NSString).substring(with: tokenRange)
            guard let priority = priorities[token.lowercased()] else { continue }

            result = NaturalPriorityParseResult(
                title: removing(tokenRange, from: text),
                value: priority.value,
                label: priority.label,
                recognizedRange: tokenRange,
                recognizedText: token
            )
        }
        return result
    }

    private static func removing(_ range: NSRange, from text: String) -> String {
        guard let range = Range(range, in: text) else { return text }
        return text.replacingCharacters(in: range, with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
