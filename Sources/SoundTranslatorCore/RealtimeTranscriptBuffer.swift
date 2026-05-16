import Foundation

public struct RealtimeTranscriptBuffer: Sendable {
    private var live = ""
    private let maxCharacters: Int

    public init(maxCharacters: Int = 420) {
        self.maxCharacters = maxCharacters
    }

    public mutating func appendDelta(_ delta: String) -> String {
        let normalized = delta.trimmingCharacters(in: .newlines)
        guard !normalized.isEmpty else {
            return displayText
        }
        live = Self.trim(live + normalized, maxCharacters: maxCharacters)
        return displayText
    }

    public mutating func complete(_ transcript: String) -> String {
        let normalized = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return displayText
        }
        if normalized.count >= live.trimmingCharacters(in: .whitespacesAndNewlines).count {
            live = Self.trim(normalized, maxCharacters: maxCharacters)
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
}
