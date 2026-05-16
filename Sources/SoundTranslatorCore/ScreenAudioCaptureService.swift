import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

public protocol AudioCaptureService: AnyObject, Sendable {
    var onAudioData: (@Sendable (Data) -> Void)? { get set }
    var onError: (@Sendable (String) -> Void)? { get set }

    func availableApplications() async throws -> [CapturableApplication]
    func start(scope: CaptureScope) async throws
    func stop() async
}

public final class ScreenAudioCaptureService: NSObject, AudioCaptureService, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    public var onAudioData: (@Sendable (Data) -> Void)?
    public var onError: (@Sendable (String) -> Void)?

    private let converter: AudioPCMConverter
    private let sampleQueue = DispatchQueue(label: "com.yurari.soundtranslator.capture.audio", qos: .userInitiated)
    private var stream: SCStream?
    private var didRequestScreenCaptureAccess = false

    public init(converter: AudioPCMConverter = AudioPCMConverter()) {
        self.converter = converter
    }

    public func availableApplications() async throws -> [CapturableApplication] {
        try requestScreenCapturePermissionIfNeeded()
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            throw SoundTranslatorError.system("ScreenCaptureKit could not list capturable apps: \(Self.describe(error))")
        }
        var seen = Set<String>()
        return content.applications
            .filter { !$0.bundleIdentifier.isEmpty && !$0.applicationName.isEmpty }
            .sorted { $0.applicationName.localizedCaseInsensitiveCompare($1.applicationName) == .orderedAscending }
            .compactMap { app in
                let key = "\(app.bundleIdentifier)-\(app.processID)"
                guard seen.insert(key).inserted else {
                    return nil
                }
                return CapturableApplication(
                    name: app.applicationName,
                    bundleIdentifier: app.bundleIdentifier,
                    processID: app.processID
                )
            }
    }

    public func start(scope: CaptureScope) async throws {
        try await stopExistingStream()
        try requestScreenCapturePermissionIfNeeded()

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            throw SoundTranslatorError.system("ScreenCaptureKit could not start capture: \(Self.describe(error))")
        }

        guard let display = content.displays.first else {
            throw SoundTranslatorError.noDisplayAvailable
        }

        let filter: SCContentFilter
        switch scope {
        case .system:
            let currentBundleID = Bundle.main.bundleIdentifier
            let currentApp = content.applications.first { $0.bundleIdentifier == currentBundleID }
            filter = SCContentFilter(
                display: display,
                excludingApplications: currentApp.map { [$0] } ?? [],
                exceptingWindows: []
            )
        case let .application(bundleIdentifier, processID):
            guard let app = content.applications.first(where: {
                $0.bundleIdentifier == bundleIdentifier && $0.processID == processID
            }) else {
                throw SoundTranslatorError.applicationNotAvailable("\(bundleIdentifier) (\(processID))")
            }
            filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        }

        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 2)
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.excludesCurrentProcessAudio = true

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.startCapture { error in
                if let error {
                    continuation.resume(throwing: SoundTranslatorError.system(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
        self.stream = stream
    }

    public func stop() async {
        try? await stopExistingStream()
    }

    private func stopExistingStream() async throws {
        guard let stream else {
            return
        }
        self.stream = nil
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.stopCapture { error in
                if let error {
                    continuation.resume(throwing: SoundTranslatorError.system(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else {
            return
        }
        do {
            let data = try converter.convert(sampleBuffer: sampleBuffer)
            if !data.isEmpty {
                onAudioData?(data)
            }
        } catch {
            onError?(error.localizedDescription)
        }
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError?(error.localizedDescription)
    }

    private func requestScreenCapturePermissionIfNeeded() throws {
        guard !CGPreflightScreenCaptureAccess() else {
            return
        }
        guard !didRequestScreenCaptureAccess else {
            throw Self.screenCapturePermissionError()
        }
        didRequestScreenCaptureAccess = true
        guard CGRequestScreenCaptureAccess() else {
            throw Self.screenCapturePermissionError()
        }
    }

    private static func screenCapturePermissionError() -> SoundTranslatorError {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.yurari.soundtranslator"
        return .permissionDenied(
            "macOS has not granted Screen & System Audio Recording to this app identity (\(bundleIdentifier)). If it already appears enabled, remove/re-add the app in Privacy settings or reset the stale TCC entry after rebuilding."
        )
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.localizedDescription) [\(nsError.domain) \(nsError.code)]"
    }
}
