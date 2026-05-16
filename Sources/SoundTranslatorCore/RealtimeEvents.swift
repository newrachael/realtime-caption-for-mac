import Foundation

public enum RealtimeInboundEvent: Equatable, Sendable {
    case outputAudioDelta(Data)
    case outputTranscriptDelta(String)
    case outputTranscriptCompleted(String)
    case inputTranscriptDelta(String)
    case inputTranscriptCompleted(String)
    case error(String)
    case other(String)
}

public struct RealtimeEventParser: Sendable {
    public init() {}

    public func parse(_ data: Data) throws -> RealtimeInboundEvent {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any],
              let type = payload["type"] as? String
        else {
            throw SoundTranslatorError.invalidServerMessage("missing event type")
        }

        switch type {
        case "error":
            let errorObject = payload["error"] as? [String: Any]
            let message = errorObject?["message"] as? String
            return .error(message ?? "Unknown realtime error")
        default:
            if Self.isOutputAudioDelta(type),
               let audio = payload["delta"] as? String,
               let decoded = Data(base64Encoded: audio) {
                return .outputAudioDelta(decoded)
            }
            if Self.isTranscriptDelta(type), Self.isOutputTranscript(type) {
                return .outputTranscriptDelta(Self.extractText(from: payload))
            }
            if Self.isTranscriptCompleted(type), Self.isOutputTranscript(type) {
                return .outputTranscriptCompleted(Self.extractText(from: payload))
            }
            if Self.isTranscriptDelta(type), Self.isInputTranscript(type) {
                return .inputTranscriptDelta(Self.extractText(from: payload))
            }
            if Self.isTranscriptCompleted(type), Self.isInputTranscript(type) {
                return .inputTranscriptCompleted(Self.extractText(from: payload))
            }
            return .other(type)
        }
    }

    private static func isTranscriptDelta(_ type: String) -> Bool {
        type.hasSuffix(".delta") && type.contains("transcript")
    }

    private static func isOutputAudioDelta(_ type: String) -> Bool {
        type.hasSuffix(".delta") && type.contains("output_audio")
    }

    private static func isTranscriptCompleted(_ type: String) -> Bool {
        (type.hasSuffix(".done") || type.hasSuffix(".completed")) && type.contains("transcript")
    }

    private static func isOutputTranscript(_ type: String) -> Bool {
        type.contains("output") || type.contains("response.audio_transcript")
    }

    private static func isInputTranscript(_ type: String) -> Bool {
        type.contains("input")
    }

    private static func extractText(from payload: [String: Any]) -> String {
        for key in ["delta", "transcript", "text"] {
            if let value = payload[key] as? String {
                return value
            }
        }
        for key in ["item", "content", "output", "input"] {
            if let nested = payload[key] as? [String: Any] {
                let value = extractText(from: nested)
                if !value.isEmpty {
                    return value
                }
            }
        }
        return ""
    }
}

public enum RealtimeOutboundEvent {
    public static func sessionUpdate(targetLanguage: String) -> Data {
        encode([
            "type": "session.update",
            "session": [
                "audio": [
                    "output": [
                        "language": targetLanguage
                    ]
                ]
            ]
        ])
    }

    public static func appendAudio(_ pcm16Data: Data) -> Data {
        encode([
            "type": "session.input_audio_buffer.append",
            "audio": pcm16Data.base64EncodedString()
        ])
    }

    private static func encode(_ payload: [String: Any]) -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            preconditionFailure("Realtime outbound payload must be JSON-serializable: \(error)")
        }
    }
}
