import Foundation

public enum CaptureScope: Codable, Equatable, Sendable {
    case system
    case application(bundleIdentifier: String, processID: Int32)

    public var displayName: String {
        switch self {
        case .system:
            "System audio"
        case let .application(bundleIdentifier, processID):
            "\(bundleIdentifier) (\(processID))"
        }
    }
}

public struct CapturableApplication: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let bundleIdentifier: String
    public let processID: Int32

    public init(name: String, bundleIdentifier: String, processID: Int32) {
        self.id = Self.captureID(bundleIdentifier: bundleIdentifier, processID: processID)
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.processID = processID
    }

    public static func captureID(bundleIdentifier: String, processID: Int32) -> String {
        "\(bundleIdentifier)-\(processID)"
    }
}

public struct TranslationLanguage: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public static let supported: [TranslationLanguage] = [
        .init(id: "en", name: "English"),
        .init(id: "ko", name: "Korean"),
        .init(id: "ja", name: "Japanese"),
        .init(id: "zh", name: "Chinese"),
        .init(id: "es", name: "Spanish"),
        .init(id: "fr", name: "French"),
        .init(id: "de", name: "German"),
        .init(id: "it", name: "Italian"),
        .init(id: "pt", name: "Portuguese"),
        .init(id: "hi", name: "Hindi"),
        .init(id: "ru", name: "Russian"),
        .init(id: "id", name: "Indonesian"),
        .init(id: "vi", name: "Vietnamese")
    ]
}

public enum ConnectionState: Equatable, Sendable {
    case idle
    case connecting
    case running
    case stopping
    case failed(String)

    public var label: String {
        switch self {
        case .idle:
            "Idle"
        case .connecting:
            "Connecting"
        case .running:
            "Running"
        case .stopping:
            "Stopping"
        case let .failed(message):
            "Failed: \(message)"
        }
    }
}

public struct SubtitleSnapshot: Equatable, Sendable {
    public var sourceText: String
    public var translatedText: String
    public var updatedAt: Date

    public init(sourceText: String = "", translatedText: String = "", updatedAt: Date = .now) {
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.updatedAt = updatedAt
    }
}

public enum SoundTranslatorError: LocalizedError, Equatable {
    case missingAPIKey
    case noDisplayAvailable
    case applicationNotAvailable(String)
    case selectedApplicationUnavailable
    case permissionDenied(String)
    case audioConversionFailed
    case websocketClosed
    case invalidServerMessage(String)
    case system(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "OpenAI API key is missing."
        case .noDisplayAvailable:
            "No display is available for ScreenCaptureKit capture."
        case let .applicationNotAvailable(bundleIdentifier):
            "The selected app is not available for capture: \(bundleIdentifier)"
        case .selectedApplicationUnavailable:
            "The selected app is not available. Refresh the app list or choose System audio explicitly."
        case let .permissionDenied(message):
            message
        case .audioConversionFailed:
            "Could not convert captured audio to 24 kHz PCM16."
        case .websocketClosed:
            "The realtime translation socket closed."
        case let .invalidServerMessage(message):
            "Unexpected realtime translation message: \(message)"
        case let .system(message):
            message
        }
    }
}
