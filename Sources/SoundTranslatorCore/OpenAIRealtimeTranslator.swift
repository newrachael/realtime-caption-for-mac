import Foundation

public protocol RealtimeTranslator: AnyObject, Sendable {
    var onTranslatedText: (@Sendable (String) -> Void)? { get set }
    var onTranslatedFinal: (@Sendable (String) -> Void)? { get set }
    var onTranslatedAudio: (@Sendable (Data) -> Void)? { get set }
    var onSourceText: (@Sendable (String) -> Void)? { get set }
    var onSourceFinal: (@Sendable (String) -> Void)? { get set }
    var onEvent: (@Sendable (String) -> Void)? { get set }
    var onError: (@Sendable (String) -> Void)? { get set }

    func connect(apiKey: String, targetLanguage: String) async throws
    func sendAudio(_ pcm16Data: Data) async
    func disconnect() async
}

public final class OpenAIRealtimeTranslator: NSObject, RealtimeTranslator, URLSessionWebSocketDelegate, @unchecked Sendable {
    public var onTranslatedText: (@Sendable (String) -> Void)?
    public var onTranslatedFinal: (@Sendable (String) -> Void)?
    public var onTranslatedAudio: (@Sendable (Data) -> Void)?
    public var onSourceText: (@Sendable (String) -> Void)?
    public var onSourceFinal: (@Sendable (String) -> Void)?
    public var onEvent: (@Sendable (String) -> Void)?
    public var onError: (@Sendable (String) -> Void)?

    private let parser = RealtimeEventParser()
    private let endpoint = URL(string: "wss://api.openai.com/v1/realtime/translations?model=gpt-realtime-translate")!
    private let lock = NSLock()
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private let sendQueue = DispatchQueue(label: "com.yurari.soundtranslator.realtime.send")
    private var isConnected = false

    public override init() {
        super.init()
    }

    public func connect(apiKey: String, targetLanguage: String) async throws {
        await disconnect()

        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.safetyIdentifierValue(), forHTTPHeaderField: "OpenAI-Safety-Identifier")

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        lock.withLock {
            self.session = session
            self.task = task
            self.isConnected = true
        }
        task.resume()

        try await sendMessage(RealtimeOutboundEvent.sessionUpdate(targetLanguage: targetLanguage))
        onEvent?("client.session_update.sent | target_language=\(targetLanguage)")
        receiveLoop()
    }

    public func sendAudio(_ pcm16Data: Data) async {
        guard lock.withLock({ isConnected }), !pcm16Data.isEmpty else {
            return
        }
        let data = RealtimeOutboundEvent.appendAudio(pcm16Data)
        do {
            try await sendMessage(data)
        } catch {
            onError?(error.localizedDescription)
        }
    }

    public func disconnect() async {
        let currentTask: URLSessionWebSocketTask?
        let currentSession: URLSession?
        (currentTask, currentSession) = lock.withLock {
            isConnected = false
            let capturedTask = task
            let capturedSession = session
            task = nil
            session = nil
            return (capturedTask, capturedSession)
        }
        currentTask?.cancel(with: .goingAway, reason: nil)
        currentSession?.invalidateAndCancel()
    }

    private func sendMessage(_ data: Data) async throws {
        let currentTask = lock.withLock { task }
        guard let currentTask else {
            throw SoundTranslatorError.websocketClosed
        }
        let text = String(decoding: data, as: UTF8.self)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sendQueue.async {
                currentTask.send(.string(text)) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func receiveLoop() {
        let currentTask = lock.withLock { isConnected ? task : nil }
        guard let currentTask else {
            return
        }
        currentTask.receive { [weak self] result in
            guard let self else {
                return
            }
            switch result {
            case let .failure(error):
                if self.lock.withLock({ self.isConnected }) {
                    self.onError?(error.localizedDescription)
                }
            case let .success(message):
                self.handle(message)
                self.receiveLoop()
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        do {
            let data: Data
            switch message {
            case let .data(value):
                data = value
            case let .string(value):
                data = Data(value.utf8)
            @unknown default:
                return
            }

            onEvent?(Self.eventSummary(from: data))
            switch try parser.parse(data) {
            case let .outputAudioDelta(audio):
                onTranslatedAudio?(audio)
            case let .outputTranscriptDelta(delta):
                onTranslatedText?(delta)
            case let .outputTranscriptCompleted(transcript):
                onTranslatedFinal?(transcript)
            case let .inputTranscriptDelta(delta):
                onSourceText?(delta)
            case let .inputTranscriptCompleted(transcript):
                onSourceFinal?(transcript)
            case let .error(message):
                onError?(message)
            case .other:
                break
            }
        } catch {
            onError?(error.localizedDescription)
        }
    }

    private static func eventSummary(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? [String: Any]
        else {
            return "unknown"
        }
        let type = payload["type"] as? String ?? "unknown"
        if type == "session.output_audio.delta",
           let audio = payload["delta"] as? String {
            let decodedBytes = Data(base64Encoded: audio)?.count ?? 0
            return "\(type) | audio_bytes=\(decodedBytes)"
        }
        guard type.contains("transcript") || type == "error" else {
            return type
        }
        let text = transcriptText(from: payload)
        guard !text.isEmpty else {
            return type
        }
        if type.contains("transcript") {
            return "\(type) | text_chars=\(text.count) text_redacted=true"
        }
        return "\(type) | \(text.prefix(80))"
    }

    private static func transcriptText(from payload: [String: Any]) -> String {
        for key in ["delta", "transcript", "text"] {
            if let value = payload[key] as? String {
                return value
            }
        }
        if let error = payload["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        for key in ["item", "content", "output", "input"] {
            if let nested = payload[key] as? [String: Any] {
                let value = transcriptText(from: nested)
                if !value.isEmpty {
                    return value
                }
            }
        }
        return ""
    }

    static func safetyIdentifierValue() -> String {
        let defaults = UserDefaults.standard
        let key = "safetyIdentifier"
        if let existing = defaults.string(forKey: key) {
            return existing
        }
        let value = UUID().uuidString.lowercased()
        defaults.set(value, forKey: key)
        return value
    }
}
