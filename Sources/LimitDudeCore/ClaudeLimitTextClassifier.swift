import Foundation

public struct ClaudeLimitTextClassifier {
    private let limitPhrases = [
        "limit reached",
        "message limit",
        "reached your message limit",
        "try again at",
        "try again later",
        "available at",
        "usage limit",
        "rate limit",
        "resets at"
    ]

    public init() {}

    public func classify(text: String) -> LimitReading {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else {
            return .unknown(reason: "No readable Claude text")
        }

        let resetText = extractResetText(from: trimmed)
        if let usagePercent = extractUsagePercent(from: normalized), usagePercent >= 80 {
            return .warning(usagePercent: usagePercent, resetText: resetText)
        }

        if normalized.contains("messages remaining") || normalized.contains("messages left") || normalized.contains("limit soon") {
            return .warning(resetText: resetText)
        }

        if limitPhrases.contains(where: normalized.contains) {
            return .limited(resetText: resetText)
        }

        return .available()
    }

    private func extractUsagePercent(from text: String) -> Int? {
        let pattern = #"(\d{1,3})\s*%"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let percentRange = Range(match.range(at: 1), in: text),
              let percent = Int(text[percentRange]) else {
            return nil
        }
        return min(percent, 100)
    }

    private func extractResetText(from text: String) -> String? {
        let patterns = [
            #"(?i)(?:resets|reset|available|try again)\s+(?:at|around|in)\s+([^\n.]+)"#,
            #"(?i)(\d{1,2}:\d{2}\s*(?:AM|PM|am|pm)?)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            return String(text[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }
}
