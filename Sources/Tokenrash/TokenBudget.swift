import Foundation

struct TokenBudget: Equatable {
    var used: Double
    var limit: Double
    var email: String?
    var resetsAt: Date?
    var label: String?

    var remaining: Double { max(0, limit - used) }

    var usedFraction: Double {
        guard limit > 0 else { return 0 }
        return min(1, max(0, used / limit))
    }

    var remainingFraction: Double { 1 - usedFraction }

    var isEmpty: Bool { remaining <= 0 || usedFraction >= 0.999 }

    var isCritical: Bool { usedFraction >= 0.9 }
}

enum TokenBudgetParser {
    static func parse(data: Data) throws -> (TokenBudget, String) {
        let object = try JSONSerialization.jsonObject(with: data)
        let pretty: String
        if let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: prettyData, encoding: .utf8) {
            pretty = text
        } else {
            pretty = String(data: data, encoding: .utf8) ?? ""
        }
        guard let budget = extract(from: object) else {
            throw ParserError.unrecognized(pretty)
        }
        return (budget, pretty)
    }

    static func parse(text: String) throws -> (TokenBudget, String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw ParserError.unrecognized(trimmed)
        }
        return try parse(data: data)
    }

    private static func extract(from object: Any) -> TokenBudget? {
        var scored: [(Int, [String: Any], String)] = []
        walk(object, path: "") { dict, path in
            if let score = score(dict) {
                scored.append((score, dict, path))
            }
        }
        guard let best = scored.max(by: { $0.0 < $1.0 }) else { return nil }
        return budget(from: best.1, email: firstEmail(in: object), path: best.2)
    }

    private static func walk(_ object: Any, path: String, visit: ([String: Any], String) -> Void) {
        if let dict = object as? [String: Any] {
            visit(dict, path)
            for (key, value) in dict {
                walk(value, path: path.isEmpty ? key : "\(path).\(key)", visit: visit)
            }
        } else if let array = object as? [Any] {
            for (i, value) in array.enumerated() {
                walk(value, path: "\(path)[\(i)]", visit: visit)
            }
        }
    }

    private static func score(_ dict: [String: Any]) -> Int? {
        let used = firstNumber(in: dict, keys: usedKeys)
        let limit = firstNumber(in: dict, keys: limitKeys)
        let remaining = firstNumber(in: dict, keys: remainingKeys)
        let percent = firstNumber(in: dict, keys: percentKeys)
        guard used != nil || remaining != nil || percent != nil else { return nil }
        guard limit != nil || remaining != nil || percent != nil else { return nil }
        var score = 0
        if used != nil { score += 3 }
        if limit != nil { score += 3 }
        if remaining != nil { score += 2 }
        if percent != nil { score += 1 }
        return score
    }

    private static func budget(from dict: [String: Any], email: String?, path: String) -> TokenBudget? {
        let usedValue = firstNumber(in: dict, keys: usedKeys)
        let limitValue = firstNumber(in: dict, keys: limitKeys)
        let remainingValue = firstNumber(in: dict, keys: remainingKeys)
        var percentValue = firstNumber(in: dict, keys: percentKeys)
        if let p = percentValue, p > 1 { percentValue = p / 100 }

        var limit = limitValue
        var used = usedValue

        if let limit, let remainingValue, used == nil {
            used = max(0, limit - remainingValue)
        } else if let used, let remainingValue, limit == nil {
            limit = used + max(0, remainingValue)
        } else if let percentValue {
            if let limit, used == nil {
                used = limit * percentValue
            } else if let used, limit == nil, percentValue > 0 {
                limit = used / percentValue
            } else if used == nil, limit == nil {
                limit = 1
                used = percentValue
            }
        }

        guard var used, var limit, limit > 0 else { return nil }
        if used > limit * 4, used > 10_000, limit < 100 {
            // Likely mixed units; keep used and treat limit as already consumed-relative.
            limit = max(limit, used)
        }
        used = min(used, limit * 1.15)

        return TokenBudget(
            used: used,
            limit: limit,
            email: email,
            resetsAt: firstDate(in: dict),
            label: path.isEmpty ? "daily" : path
        )
    }

    private static func firstEmail(in object: Any) -> String? {
        var found: String?
        walk(object, path: "") { dict, _ in
            if found == nil {
                found = firstString(in: dict, keys: ["email", "user_email", "userEmail"])
            }
        }
        return found
    }

    private static func firstNumber(in dict: [String: Any], keys: [String]) -> Double? {
        let mapped = Dictionary(uniqueKeysWithValues: dict.map { ($0.key.lowercased(), $0.value) })
        for key in keys {
            if let value = number(mapped[key.lowercased()]) { return value }
        }
        for (key, value) in mapped {
            if keys.contains(where: { key == $0 || key.hasSuffix("_\($0)") || key.hasSuffix($0) }) {
                if let number = number(value) { return number }
            }
        }
        return nil
    }

    private static func firstString(in dict: [String: Any], keys: [String]) -> String? {
        let mapped = Dictionary(uniqueKeysWithValues: dict.map { ($0.key.lowercased(), $0.value) })
        for key in keys {
            if let value = mapped[key.lowercased()] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    private static func firstDate(in dict: [String: Any]) -> Date? {
        let keys = ["resets_at", "reset_at", "resetsAt", "resetAt", "reset_time", "next_reset"]
        guard let raw = firstString(in: dict, keys: keys) else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let n as Double: return n
        case let n as Float: return Double(n)
        case let n as Int: return Double(n)
        case let n as Int64: return Double(n)
        case let n as NSNumber: return n.doubleValue
        case let s as String:
            let cleaned = s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
            return Double(cleaned)
        default: return nil
        }
    }

    private static let usedKeys = [
        "used", "usage", "spent", "consumed", "tokens_used", "used_tokens",
        "daily_used", "tokens", "total_tokens", "prompt_tokens", "current"
    ]
    private static let limitKeys = [
        "limit", "budget", "cap", "quota", "daily_budget", "daily_limit",
        "max", "allowance", "tokens_limit", "token_budget", "daily_quota"
    ]
    private static let remainingKeys = [
        "remaining", "left", "tokens_remaining", "remaining_tokens", "available"
    ]
    private static let percentKeys = [
        "percent", "percentage", "used_pct", "pct", "fraction", "used_fraction"
    ]

    enum ParserError: LocalizedError {
        case unrecognized(String)
        var errorDescription: String? {
            switch self {
            case .unrecognized: return "Could not find a daily used/limit pair in /me"
            }
        }
    }
}

enum TokenFormat {
    static func tokens(_ value: Double) -> String {
        let abs = Swift.abs(value)
        switch abs {
        case 1_000_000_000...: return String(format: "%.1fB", value / 1_000_000_000).replacingOccurrences(of: ".0B", with: "B")
        case 1_000_000...: return String(format: "%.1fM", value / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
        case 10_000...: return String(format: "%.0fK", value / 1_000)
        case 1_000...: return String(format: "%.1fK", value / 1_000).replacingOccurrences(of: ".0K", with: "K")
        default: return String(format: "%.0f", value)
        }
    }

    static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", (fraction * 100).rounded())
    }

    static func countdown(to date: Date, now: Date = Date()) -> String {
        let remaining = max(0, date.timeIntervalSince(now))
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    static func nextMidnight(from now: Date = Date()) -> Date {
        Calendar.current.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(86_400)
    }
}
