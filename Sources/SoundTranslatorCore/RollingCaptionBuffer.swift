import Foundation

public struct RollingCaptionBuffer: Sendable {
    private var live = ""
    private let maxCharacters: Int

    public init(maxCommittedLines: Int = 2, maxCharacters: Int = 420) {
        self.maxCharacters = maxCharacters
    }

    public mutating func appendDelta(_ delta: String) -> String {
        let normalized = delta.trimmingCharacters(in: .newlines)
        if Self.isReplacement(current: live, next: normalized) {
            live = Self.trim(normalized, maxCharacters: maxCharacters)
        } else if !Self.isDuplicate(current: live, next: normalized) {
            live = Self.trim(Self.join(live, normalized), maxCharacters: maxCharacters)
        }
        return displayText
    }

    public mutating func complete(_ transcript: String) -> String {
        let normalized = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            return displayText
        }
        if Self.isReplacement(current: live, next: normalized) {
            live = Self.trim(normalized, maxCharacters: maxCharacters)
        } else if !Self.isDuplicate(current: live, next: normalized) {
            live = Self.trim(Self.joinSegment(live, normalized), maxCharacters: maxCharacters)
        }
        return displayText
    }

    public mutating func clear() {
        live = ""
    }

    public var displayText: String {
        Self.trim(live.trimmingCharacters(in: .whitespacesAndNewlines), maxCharacters: maxCharacters)
    }

    private static func trim(_ text: String, maxCharacters: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if normalized.count <= maxCharacters {
            return normalized
        }
        return String(normalized.suffix(maxCharacters))
    }

    private static func join(_ current: String, _ delta: String) -> String {
        guard !current.isEmpty else {
            return delta
        }
        guard !delta.isEmpty else {
            return current
        }
        if current.last?.isWhitespace == true || delta.first?.isWhitespace == true {
            return current + delta
        }
        if delta.first?.isPunctuation == true {
            return current + delta
        }
        if shouldInsertSpaceBetween(current.last, delta.first) {
            return current + " " + delta
        }
        return current + delta
    }

    private static func joinSegment(_ current: String, _ segment: String) -> String {
        guard !current.isEmpty else {
            return segment
        }
        guard !segment.isEmpty else {
            return current
        }
        return join(current, segment)
    }

    private static func isReplacement(current: String, next: String) -> Bool {
        guard !current.isEmpty, !next.isEmpty else {
            return !next.isEmpty && current.isEmpty
        }
        if next == current {
            return true
        }
        if next.count > current.count, next.hasPrefix(current) || next.contains(current) {
            return true
        }
        return false
    }

    private static func isDuplicate(current: String, next: String) -> Bool {
        guard !current.isEmpty, !next.isEmpty else {
            return next.isEmpty
        }
        return current == next || current.hasSuffix(next)
    }

    private static func shouldInsertSpaceBetween(_ lhs: Character?, _ rhs: Character?) -> Bool {
        guard let lhs, let rhs else {
            return false
        }
        return lhs.isASCIIAlphanumeric && rhs.isASCIIAlphanumeric
    }
}

private extension Character {
    var isASCIIAlphanumeric: Bool {
        unicodeScalars.count == 1 && unicodeScalars.allSatisfy { scalar in
            (65...90).contains(Int(scalar.value)) ||
            (97...122).contains(Int(scalar.value)) ||
            (48...57).contains(Int(scalar.value))
        }
    }
}
