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
        return try parse(object: object, fallbackPretty: String(data: data, encoding: .utf8) ?? "")
    }

    static func parse(text: String) throws -> (TokenBudget, String) {
        let blob = extractJSONBlob(from: text) ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = blob.data(using: .utf8) else {
            throw ParserError.unrecognized(text)
        }
        do {
            return try parse(data: data)
        } catch {
            throw ParserError.unrecognized(blob)
        }
    }

    private static func parse(object: Any, fallbackPretty: String) throws -> (TokenBudget, String) {
        let pretty: String
        if let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: prettyData, encoding: .utf8) {
            pretty = text
        } else {
            pretty = fallbackPretty
        }
        guard let budget = extract(from: object) else {
            throw ParserError.unrecognized(pretty)
        }
        return (budget, pretty)
    }

    static func extractJSONBlob(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return trimmed }
        guard let start = trimmed.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
        let open = trimmed[start]
        let close: Character = open == "{" ? "}" : "]"
        if let end = trimmed.lastIndex(of: close), end >= start {
            return String(trimmed[start...end])
        }
        return nil
    }

    private static func extract(from object: Any) -> TokenBudget? {
        if let tokendash = tokendashToday(from: object) {
            return tokendash
        }
        if let sameDict = bestSameDict(in: object) {
            return sameDict
        }
        return pairedAcrossTree(object)
    }

    /// `{ today: { spend_usd, effective_limit_usd, standing_limit_usd } }` — spend is used, not remaining.
    private static func tokendashToday(from object: Any) -> TokenBudget? {
        guard let root = object as? [String: Any],
              let today = root["today"] as? [String: Any] else { return nil }
        let used = number(today["spend_usd"])
        let limit = number(today["effective_limit_usd"])
            ?? number(today["standing_limit_usd"])
            ?? number(today["limit_usd"])
        guard let used, let limit, limit > 0 else { return nil }
        return TokenBudget(
            used: used,
            limit: limit,
            email: firstEmail(in: object),
            resetsAt: firstDate(in: today) ?? firstDate(in: object),
            label: "today"
        )
    }

    private static func bestSameDict(in object: Any) -> TokenBudget? {
        var scored: [(Int, TokenBudget)] = []
        walk(object, path: "") { dict, path in
            if let budget = budget(from: dict, email: firstEmail(in: object), path: path) {
                var score = 4
                let p = path.lowercased()
                if p.contains("daily") || p.contains("today") { score += 6 }
                if p.contains("budget") || p.contains("quota") { score += 3 }
                scored.append((score, budget))
            }
        }
        return scored.max(by: { $0.0 < $1.0 })?.1
    }

    private static func pairedAcrossTree(_ object: Any) -> TokenBudget? {
        var fields: [NumField] = []
        flatten(object, path: "", into: &fields)
        let useds = fields.filter { $0.kind == .used }
        let limits = fields.filter { $0.kind == .limit }
        let remainings = fields.filter { $0.kind == .remaining }
        let percents = fields.filter { $0.kind == .percent }

        var best: (Int, Double, Double, String)?

        func consider(used: Double, limit: Double, path: String, score: Int) {
            guard limit > 0 else { return }
            if let current = best, current.0 >= score { return }
            best = (score, used, limit, path)
        }

        for used in useds {
            for limit in limits where used.path != limit.path {
                var score = 1
                if parentPath(used.path) == parentPath(limit.path) { score += 10 }
                if used.path.lowercased().contains("daily") || limit.path.lowercased().contains("daily") { score += 6 }
                if used.path.lowercased().contains("today") || limit.path.lowercased().contains("today") { score += 5 }
                consider(used: used.value, limit: limit.value, path: "\(used.path)+\(limit.path)", score: score)
            }
        }

        if best == nil, let used = useds.max(by: { $0.value < $1.value }), let remaining = remainings.first {
            consider(used: used.value, limit: used.value + max(0, remaining.value), path: used.path, score: 3)
        }
        if best == nil, let limit = limits.first, let remaining = remainings.first {
            consider(used: max(0, limit.value - remaining.value), limit: limit.value, path: limit.path, score: 3)
        }
        if best == nil, let percent = percents.first {
            let fraction = percent.value > 1 ? percent.value / 100 : percent.value
            if let limit = limits.first {
                consider(used: limit.value * fraction, limit: limit.value, path: percent.path, score: 2)
            } else {
                consider(used: fraction, limit: 1, path: percent.path, score: 1)
            }
        }

        guard let best else { return nil }
        return TokenBudget(
            used: min(best.1, best.2 * 1.15),
            limit: best.2,
            email: firstEmail(in: object),
            resetsAt: firstDate(in: object),
            label: best.3
        )
    }

    private static func flatten(_ object: Any, path: String, into fields: inout [NumField]) {
        if let dict = object as? [String: Any] {
            for (key, value) in dict {
                let next = path.isEmpty ? key : "\(path).\(key)"
                if let number = number(value), let kind = kind(forKey: key) {
                    fields.append(NumField(path: next, key: key, value: number, kind: kind))
                } else {
                    flatten(value, path: next, into: &fields)
                }
            }
        } else if let array = object as? [Any] {
            for (i, value) in array.enumerated() {
                flatten(value, path: "\(path)[\(i)]", into: &fields)
            }
        }
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

    private static func budget(from dict: [String: Any], email: String?, path: String) -> TokenBudget? {
        let usedValue = firstNumber(in: dict, kinds: [.used])
        let limitValue = firstNumber(in: dict, kinds: [.limit])
        let remainingValue = firstNumber(in: dict, kinds: [.remaining])
        var percentValue = firstNumber(in: dict, kinds: [.percent])
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

    private static func firstDate(in object: Any) -> Date? {
        var found: Date?
        walk(object, path: "") { dict, _ in
            if found == nil {
                found = firstDate(in: dict)
            }
        }
        return found
    }

    private static func firstNumber(in dict: [String: Any], kinds: Set<Kind>) -> Double? {
        for (key, value) in dict {
            guard let kind = kind(forKey: key), kinds.contains(kind) else { continue }
            if let number = number(value) { return number }
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

    private static func kind(forKey raw: String) -> Kind? {
        let key = raw.lowercased()
        if ignoredKeys.contains(where: { key == $0 || key.hasSuffix("_\($0)") }) { return nil }
        if key.contains("percent") || key.hasSuffix("pct") || key.contains("fraction") { return .percent }
        if key.contains("remain") || key == "left" || key.contains("available") { return .remaining }
        if key.contains("limit") || key.contains("budget") || key.contains("quota")
            || key.contains("allowance") || key == "cap" || key.hasSuffix("_max") || key == "max" {
            return .limit
        }
        if key.contains("used") || key.contains("usage") || key.contains("spent") || key.contains("spend")
            || key.contains("consumed") || key.contains("cost") || key == "tokens"
            || key.contains("tokens") || key == "current" {
            return .used
        }
        return nil
    }

    private static func parentPath(_ path: String) -> String {
        if let idx = path.lastIndex(of: ".") { return String(path[..<idx]) }
        return ""
    }

    private static let ignoredKeys: Set<String> = [
        "id", "status", "code", "port", "ttl", "exp", "iat", "width", "height",
        "timestamp", "created", "updated", "year", "month", "day", "hour"
    ]

    private struct NumField {
        var path: String
        var key: String
        var value: Double
        var kind: Kind
    }

    private enum Kind {
        case used, limit, remaining, percent
    }

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
    static func usd(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    static func tokens(_ value: Double) -> String { usd(value) }

    static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", (fraction * 100).rounded())
    }

    static func countdown(to date: Date, now: Date = Date()) -> String {
        let remaining = max(0, Int(date.timeIntervalSince(now).rounded()))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let seconds = remaining % 60
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    static func nextMidnight(from now: Date = Date()) -> Date {
        Calendar.current.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(86_400)
    }
}
