import AppKit
import Foundation
import SoundTranslatorCore
import UniformTypeIdentifiers

@MainActor
final class AppViewModel: ObservableObject {
    private static let diagnosticsBuildMarker = "2026-05-16.realtime-translation-only.redacted-diagnostics-v9"
    private static let diagnosticsDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/SoundTranslator", isDirectory: true)

    @Published var apiKey: String = ""
    @Published var targetLanguage: String
    @Published var captureSystemAudio: Bool
    @Published var selectedApplicationID: String?
    private var restoredApplicationScope: CaptureScope?
    @Published var applications: [CapturableApplication] = []
    @Published var state: ConnectionState = .idle
    @Published var sourceText: String = ""
    @Published var translatedText: String = ""
    @Published var overlayOpacity: Double
    @Published var overlayFontSize: Double
    @Published var showDockIcon: Bool
    @Published var lastError: String?
    @Published var audioLevel: Double = 0
    @Published var audioBytesSent: Int = 0
    @Published var audioPacketCount: Int = 0
    @Published var realtimeEventCount: Int = 0
    @Published var translatedEventCount: Int = 0
    @Published var sourceEventCount: Int = 0
    @Published var lastRealtimeEvent: String = "none"
    @Published var lastAudioDescription: String = "no audio yet"
    @Published var lastInputAudioDumpPath: String?
    @Published var recentRealtimeEvents: [String] = []

    let languages = TranslationLanguage.supported

    private let settings: SettingsStore
    private let translator: RealtimeTranslator
    private let captureService: AudioCaptureService
    private let audioSender: AudioSendBuffer
    private let inputAudioRecorder = WAVAudioRecorder()
    private var clearTask: Task<Void, Never>?
    private var isCleaningUpAfterFailure = false
    private var translatedCaption = RealtimeTranscriptBuffer()
    private var sourceCaption = RealtimeTranscriptBuffer(maxCharacters: 240)
    private var translatedPublishTask: Task<Void, Never>?
    private var sourcePublishTask: Task<Void, Never>?
    private var transcriptAvailabilityTask: Task<Void, Never>?
    private var debugWAVTask: Task<Void, Never>?
    private var diagnosticSessionID = UUID().uuidString
    private var translatedAudioDeltaCount = 0
    private var translatedAudioBytes = 0

    init(
        settings: SettingsStore = .shared,
        translator: RealtimeTranslator = OpenAIRealtimeTranslator(),
        captureService: AudioCaptureService = ScreenAudioCaptureService()
    ) {
        self.settings = settings
        self.translator = translator
        self.captureService = captureService
        self.audioSender = AudioSendBuffer(translator: translator)
        self.targetLanguage = settings.targetLanguage
        self.overlayOpacity = settings.overlayOpacity
        self.overlayFontSize = settings.overlayFontSize
        self.showDockIcon = settings.showDockIcon

        switch settings.captureScope {
        case .system:
            self.captureSystemAudio = true
            self.selectedApplicationID = nil
        case let .application(bundleIdentifier, processID):
            self.captureSystemAudio = false
            self.restoredApplicationScope = .application(bundleIdentifier: bundleIdentifier, processID: processID)
            self.selectedApplicationID = CapturableApplication.captureID(
                bundleIdentifier: bundleIdentifier,
                processID: processID
            )
        }

        do {
            self.apiKey = try settings.loadAPIKey() ?? ""
        } catch {
            self.apiKey = ""
            self.lastError = error.localizedDescription
        }
        bindServices()
        applyActivationPolicy()
    }

    var canStart: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && state != .running && state != .connecting
    }

    var selectedLanguageName: String {
        languages.first(where: { $0.id == targetLanguage })?.name ?? targetLanguage
    }

    func refreshApplications() async {
        do {
            applications = try await captureService.availableApplications()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func requestCapturePermission() async {
        do {
            applications = try await captureService.availableApplications()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        openScreenAudioPrivacy()
    }

    func saveSettings() {
        settings.targetLanguage = targetLanguage
        settings.overlayOpacity = overlayOpacity
        settings.overlayFontSize = overlayFontSize
        settings.showDockIcon = showDockIcon
        if captureSystemAudio {
            settings.captureScope = .system
        } else if let selectedApplication = selectedApplication() {
            settings.captureScope = .application(
                bundleIdentifier: selectedApplication.bundleIdentifier,
                processID: selectedApplication.processID
            )
        }
        do {
            try settings.saveAPIKey(apiKey)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setShowDockIcon(_ value: Bool) {
        showDockIcon = value
        settings.showDockIcon = value
        applyActivationPolicy()
    }

    func toggleRunning() async {
        if state == .running || state == .connecting {
            await stop()
        } else {
            await startTranslation()
        }
    }

    func selectAndTranslateDebugWAV() {
        guard canStart else {
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Choose Realtime Caption for Mac Debug WAV"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.wav]
        panel.directoryURL = Self.diagnosticsDirectory

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        debugWAVTask?.cancel()
        debugWAVTask = Task { [weak self] in
            await self?.translateDebugWAV(url)
        }
    }

    func startTranslation() async {
        debugWAVTask?.cancel()
        debugWAVTask = nil
        saveSettings()
        let storedKey: String
        do {
            storedKey = try settings.loadAPIKey() ?? ""
        } catch {
            let message = error.localizedDescription
            lastError = message
            state = .failed(message)
            return
        }
        guard !storedKey.isEmpty else {
            let message = SoundTranslatorError.missingAPIKey.localizedDescription
            lastError = message
            state = .failed(message)
            return
        }

        sourceText = ""
        translatedText = ""
        audioLevel = 0
        audioBytesSent = 0
        audioPacketCount = 0
        translatedAudioDeltaCount = 0
        translatedAudioBytes = 0
        realtimeEventCount = 0
        translatedEventCount = 0
        sourceEventCount = 0
        lastRealtimeEvent = "none"
        lastAudioDescription = "waiting for audio"
        lastInputAudioDumpPath = nil
        recentRealtimeEvents = []
        translatedCaption.clear()
        sourceCaption.clear()
        translatedPublishTask?.cancel()
        sourcePublishTask?.cancel()
        transcriptAvailabilityTask?.cancel()
        translatedPublishTask = nil
        sourcePublishTask = nil
        transcriptAvailabilityTask = nil
        lastError = nil
        state = .connecting
        diagnosticSessionID = UUID().uuidString
        DiagnosticsLogger.resetSession(id: diagnosticSessionID)
        DiagnosticsLogger.log("CONFIG build_marker=\(Self.diagnosticsBuildMarker) caption_buffer=realtime_append_v3 target_language=\(targetLanguage) selected_language=\(selectedLanguageName) capture_scope=\(diagnosticScopeDescription()) api_key_present=\(!storedKey.isEmpty) bundle_id=\(Bundle.main.bundleIdentifier ?? "unknown") executable=\(Bundle.main.executableURL?.path ?? "unknown")")
        do {
            let dumpURL = try await inputAudioRecorder.start(
                directory: Self.diagnosticsDirectory,
                sessionID: diagnosticSessionID
            )
            lastInputAudioDumpPath = dumpURL.path
            DiagnosticsLogger.log("INPUT_AUDIO_DUMP_START format=wav sample_rate=24000 channels=1 bits_per_sample=16 path=\(Self.logSafe(dumpURL.path))")
        } catch {
            DiagnosticsLogger.log("INPUT_AUDIO_DUMP_START_FAILED error=\(Self.logSafe(error.localizedDescription))")
        }

        do {
            guard let scope = currentScope() else {
                throw SoundTranslatorError.selectedApplicationUnavailable
            }
            DiagnosticsLogger.log("TRANSLATION_CONNECT_BEGIN endpoint=/v1/realtime/translations model=gpt-realtime-translate target_language=\(targetLanguage)")
            try await translator.connect(apiKey: storedKey, targetLanguage: targetLanguage)
            DiagnosticsLogger.log("TRANSLATION_CONNECT_OK")
            DiagnosticsLogger.log("CAPTURE_START_BEGIN scope=\(scope.displayName)")
            try await captureService.start(scope: scope)
            DiagnosticsLogger.log("CAPTURE_START_OK scope=\(scope.displayName)")
            state = .running
            DiagnosticsLogger.log("STATE running")
        } catch {
            if let dumpURL = try? await inputAudioRecorder.stop() {
                DiagnosticsLogger.log("INPUT_AUDIO_DUMP_STOP path=\(Self.logSafe(dumpURL.path))")
            }
            await captureService.stop()
            await translator.disconnect()
            let message = error.localizedDescription
            lastError = message
            state = .failed(message)
            DiagnosticsLogger.log("START_FAILED error=\(Self.logSafe(message))")
        }
    }

    private func translateDebugWAV(_ url: URL) async {
        saveSettings()
        let storedKey: String
        do {
            storedKey = try settings.loadAPIKey() ?? ""
        } catch {
            failBeforeStart(error.localizedDescription)
            return
        }
        guard !storedKey.isEmpty else {
            failBeforeStart(SoundTranslatorError.missingAPIKey.localizedDescription)
            return
        }

        let audio: WAVPCM16Audio
        do {
            audio = try WAVPCM16FileReader.read(url: url)
        } catch {
            failBeforeStart(error.localizedDescription)
            return
        }

        sourceText = ""
        translatedText = ""
        audioLevel = 0
        audioBytesSent = 0
        audioPacketCount = 0
        translatedAudioDeltaCount = 0
        translatedAudioBytes = 0
        realtimeEventCount = 0
        translatedEventCount = 0
        sourceEventCount = 0
        lastRealtimeEvent = "none"
        lastAudioDescription = "debug WAV selected"
        lastInputAudioDumpPath = url.path
        recentRealtimeEvents = []
        translatedCaption.clear()
        sourceCaption.clear()
        translatedPublishTask?.cancel()
        sourcePublishTask?.cancel()
        transcriptAvailabilityTask?.cancel()
        translatedPublishTask = nil
        sourcePublishTask = nil
        transcriptAvailabilityTask = nil
        lastError = nil
        state = .connecting
        diagnosticSessionID = UUID().uuidString
        DiagnosticsLogger.resetSession(id: diagnosticSessionID)
        DiagnosticsLogger.log("CONFIG build_marker=\(Self.diagnosticsBuildMarker) caption_buffer=realtime_append_v3 target_language=\(targetLanguage) selected_language=\(selectedLanguageName) capture_scope=debug_wav api_key_present=\(!storedKey.isEmpty) bundle_id=\(Bundle.main.bundleIdentifier ?? "unknown") executable=\(Bundle.main.executableURL?.path ?? "unknown")")
        DiagnosticsLogger.log("DEBUG_WAV_SELECTED path=\(Self.logSafe(url.path)) bytes=\(audio.pcm16Data.count) sample_rate=\(audio.sampleRate) channels=\(audio.channelCount) bits_per_sample=\(audio.bitsPerSample)")

        do {
            DiagnosticsLogger.log("TRANSLATION_CONNECT_BEGIN endpoint=/v1/realtime/translations model=gpt-realtime-translate target_language=\(targetLanguage)")
            try await translator.connect(apiKey: storedKey, targetLanguage: targetLanguage)
            DiagnosticsLogger.log("TRANSLATION_CONNECT_OK")
            state = .running
            DiagnosticsLogger.log("STATE running mode=debug_wav")

            await feedDebugWAV(audio.pcm16Data)
            guard !Task.isCancelled, state == .running else {
                return
            }
            DiagnosticsLogger.log("DEBUG_WAV_FEED_DONE audio_packets=\(audioPacketCount) audio_bytes=\(audioBytesSent)")
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, state == .running else {
                return
            }
            await translator.disconnect()
            state = .idle
            DiagnosticsLogger.log("STATE idle debug_wav_done=true audio_packets=\(audioPacketCount) audio_bytes=\(audioBytesSent) translated_audio_deltas=\(translatedAudioDeltaCount) translated_audio_bytes=\(translatedAudioBytes) transcript_events=\(translatedEventCount) source_events=\(sourceEventCount)")
        } catch {
            await translator.disconnect()
            let message = error.localizedDescription
            lastError = message
            state = .failed(message)
            DiagnosticsLogger.log("DEBUG_WAV_FAILED error=\(Self.logSafe(message))")
        }
    }

    private func feedDebugWAV(_ pcm16Data: Data) async {
        let targetChunkBytes = 960
        var offset = 0
        while offset < pcm16Data.count, !Task.isCancelled, state == .running {
            let end = min(offset + targetChunkBytes, pcm16Data.count)
            let chunk = pcm16Data.subdata(in: offset..<end)
            recordAudioData(chunk)
            await audioSender.enqueue(chunk)
            offset = end

            let samples = max(1, chunk.count / 2)
            let nanoseconds = UInt64((Double(samples) / 24_000.0) * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
        }
    }

    private func failBeforeStart(_ message: String) {
        lastError = message
        state = .failed(message)
        DiagnosticsLogger.log("START_FAILED error=\(Self.logSafe(message))")
    }

    func stop() async {
        guard state != .idle else {
            return
        }
        state = .stopping
        debugWAVTask?.cancel()
        debugWAVTask = nil
        translatedPublishTask?.cancel()
        sourcePublishTask?.cancel()
        transcriptAvailabilityTask?.cancel()
        translatedPublishTask = nil
        sourcePublishTask = nil
        transcriptAvailabilityTask = nil
        await captureService.stop()
        await translator.disconnect()
        if let dumpURL = try? await inputAudioRecorder.stop() {
            lastInputAudioDumpPath = dumpURL.path
            DiagnosticsLogger.log("INPUT_AUDIO_DUMP_STOP path=\(Self.logSafe(dumpURL.path))")
        }
        state = .idle
        DiagnosticsLogger.log("STATE idle stop_requested=true audio_packets=\(audioPacketCount) audio_bytes=\(audioBytesSent) translated_audio_deltas=\(translatedAudioDeltaCount) translated_audio_bytes=\(translatedAudioBytes) transcript_events=\(translatedEventCount) source_events=\(sourceEventCount)")
    }

    func openScreenAudioPrivacy() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    func openDiagnosticsFolder() {
        NSWorkspace.shared.open(Self.diagnosticsDirectory)
    }

    func quitApplication() async {
        await stop()
        NSApp.terminate(nil)
    }

    private func currentScope() -> CaptureScope? {
        if captureSystemAudio {
            return .system
        }
        if let selectedApplication = selectedApplication() {
            return .application(
                bundleIdentifier: selectedApplication.bundleIdentifier,
                processID: selectedApplication.processID
            )
        }
        return restoredApplicationScope
    }

    private func selectedApplication() -> CapturableApplication? {
        guard let selectedApplicationID, !selectedApplicationID.isEmpty else {
            return nil
        }
        return applications.first { $0.id == selectedApplicationID }
    }

    private func bindServices() {
        translator.onTranslatedText = { [weak self] delta in
            Task { @MainActor in
                self?.appendTranslated(delta)
            }
        }
        translator.onTranslatedFinal = { [weak self] transcript in
            Task { @MainActor in
                self?.completeTranslated(transcript)
            }
        }
        translator.onTranslatedAudio = { [weak self] data in
            Task { @MainActor in
                self?.recordTranslatedAudioDelta(data)
            }
        }
        translator.onSourceText = { [weak self] delta in
            Task { @MainActor in
                self?.appendSource(delta)
            }
        }
        translator.onSourceFinal = { [weak self] transcript in
            Task { @MainActor in
                self?.completeSource(transcript)
            }
        }
        translator.onEvent = { [weak self] type in
            Task { @MainActor in
                self?.recordRealtimeEvent(type)
            }
        }
        translator.onError = { [weak self] message in
            Task { @MainActor in
                self?.failAndStop(message)
            }
        }
        captureService.onAudioData = { [weak self] data in
            Task {
                await MainActor.run {
                    self?.recordAudioData(data)
                }
                await self?.audioSender.enqueue(data)
                await self?.inputAudioRecorder.append(data)
            }
        }
        captureService.onError = { [weak self] message in
            Task { @MainActor in
                self?.failAndStop(message)
            }
        }
    }

    private func failAndStop(_ message: String) {
        guard !isCleaningUpAfterFailure else {
            return
        }
        isCleaningUpAfterFailure = true
        lastError = message
        state = .failed(message)
        DiagnosticsLogger.log("STATE failed error=\(Self.logSafe(message)) audio_packets=\(audioPacketCount) audio_bytes=\(audioBytesSent) translated_audio_deltas=\(translatedAudioDeltaCount) translated_audio_bytes=\(translatedAudioBytes) transcript_events=\(translatedEventCount) source_events=\(sourceEventCount) last_event=\(Self.logSafe(lastRealtimeEvent))")
        Task { [weak self] in
            guard let self else {
                return
            }
            await self.captureService.stop()
            await self.translator.disconnect()
            if let dumpURL = try? await self.inputAudioRecorder.stop() {
                DiagnosticsLogger.log("INPUT_AUDIO_DUMP_STOP path=\(Self.logSafe(dumpURL.path))")
            }
            await MainActor.run {
                self.isCleaningUpAfterFailure = false
            }
        }
    }

    private func appendTranslated(_ delta: String) {
        transcriptAvailabilityTask?.cancel()
        transcriptAvailabilityTask = nil
        translatedEventCount += 1
        _ = translatedCaption.appendDelta(delta)
        let displayText = translatedCaption.displayText
        if Self.shouldLogTranscriptDelta(count: translatedEventCount, displayText: displayText) {
            DiagnosticsLogger.log("TRANSCRIPT_DELTA target count=\(translatedEventCount) delta_chars=\(delta.count) display_chars=\(displayText.count) text_redacted=true")
        }
        if displayText.hasSentenceBoundary {
            translatedPublishTask?.cancel()
            translatedPublishTask = nil
            publishTranslatedNow()
        } else {
            scheduleTranslatedPublish()
        }
        scheduleClearIfQuiet()
    }

    private func completeTranslated(_ transcript: String) {
        transcriptAvailabilityTask?.cancel()
        transcriptAvailabilityTask = nil
        translatedEventCount += 1
        _ = translatedCaption.complete(transcript)
        DiagnosticsLogger.log("TRANSCRIPT_FINAL target count=\(translatedEventCount) transcript_chars=\(transcript.count) display_chars=\(translatedCaption.displayText.count) text_redacted=true")
        publishTranslatedNow()
        scheduleClearIfQuiet()
    }

    private func appendSource(_ delta: String) {
        sourceEventCount += 1
        _ = sourceCaption.appendDelta(delta)
        let displayText = sourceCaption.displayText
        if Self.shouldLogTranscriptDelta(count: sourceEventCount, displayText: displayText) {
            DiagnosticsLogger.log("TRANSCRIPT_DELTA source count=\(sourceEventCount) delta_chars=\(delta.count) display_chars=\(displayText.count) text_redacted=true")
        }
        if displayText.hasSentenceBoundary {
            sourcePublishTask?.cancel()
            sourcePublishTask = nil
            publishSourceNow()
        } else {
            scheduleSourcePublish()
        }
        scheduleClearIfQuiet()
    }

    private func completeSource(_ transcript: String) {
        sourceEventCount += 1
        _ = sourceCaption.complete(transcript)
        DiagnosticsLogger.log("TRANSCRIPT_FINAL source count=\(sourceEventCount) transcript_chars=\(transcript.count) display_chars=\(sourceCaption.displayText.count) text_redacted=true")
        publishSourceNow()
        scheduleClearIfQuiet()
    }

    private func recordAudioData(_ data: Data) {
        audioPacketCount += 1
        audioBytesSent += data.count
        audioLevel = Self.pcm16Level(data)
        lastAudioDescription = "\(Self.byteCountFormatter.string(fromByteCount: Int64(audioBytesSent))) sent, level \(Int(audioLevel * 100))%"
        if audioPacketCount == 1 || audioPacketCount % 25 == 0 {
            DiagnosticsLogger.log("CAPTURE_AUDIO packet=\(audioPacketCount) bytes=\(data.count) total_bytes=\(audioBytesSent) level=\(String(format: "%.4f", audioLevel))")
        }
    }

    private func recordTranslatedAudioDelta(_ data: Data) {
        translatedAudioDeltaCount += 1
        translatedAudioBytes += data.count
        if translatedAudioDeltaCount == 1 || translatedAudioDeltaCount % 25 == 0 {
            DiagnosticsLogger.log("TRANSLATED_AUDIO_DELTA count=\(translatedAudioDeltaCount) bytes=\(data.count) total_bytes=\(translatedAudioBytes) transcript_events=\(translatedEventCount)")
        }
        guard !data.isEmpty, translatedEventCount == 0, transcriptAvailabilityTask == nil else {
            return
        }
        DiagnosticsLogger.log("TRANSCRIPT_WATCHDOG_ARMED reason=translated_audio_received_without_transcript timeout_seconds=15")
        transcriptAvailabilityTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            await MainActor.run {
                guard let self,
                      self.state == .running,
                      self.translatedEventCount == 0,
                      self.audioPacketCount > 0
                else {
                    return
                }
                DiagnosticsLogger.log("TRANSCRIPT_WATCHDOG_FAILED translated_audio_deltas=\(self.translatedAudioDeltaCount) translated_audio_bytes=\(self.translatedAudioBytes) audio_packets=\(self.audioPacketCount) transcript_events=0")
                self.failAndStop(
                    "OpenAI Realtime Translation returned session.output_audio.delta but no session.output_transcript.delta within 15 seconds. Realtime Caption for Mac only uses gpt-realtime-translate transcript output, so subtitles are unavailable for this session."
                )
            }
        }
    }

    private func recordRealtimeEvent(_ type: String) {
        realtimeEventCount += 1
        lastRealtimeEvent = type
        recentRealtimeEvents.append(type)
        if recentRealtimeEvents.count > 12 {
            recentRealtimeEvents.removeFirst(recentRealtimeEvents.count - 12)
        }
        Self.appendRealtimeLog(type)
        DiagnosticsLogger.log("REALTIME_EVENT count=\(realtimeEventCount) event=\(Self.logSafe(type)) audio_packets=\(audioPacketCount) translated_audio_deltas=\(translatedAudioDeltaCount) transcript_events=\(translatedEventCount) source_events=\(sourceEventCount)")
    }

    private func scheduleTranslatedPublish() {
        guard translatedPublishTask == nil else {
            return
        }
        translatedPublishTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            await MainActor.run {
                guard !Task.isCancelled else {
                    return
                }
                self?.translatedPublishTask = nil
                self?.publishTranslatedIfReadable()
            }
        }
    }

    private func scheduleSourcePublish() {
        guard sourcePublishTask == nil else {
            return
        }
        sourcePublishTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            await MainActor.run {
                guard !Task.isCancelled else {
                    return
                }
                self?.sourcePublishTask = nil
                self?.publishSourceIfReadable()
            }
        }
    }

    private func publishTranslatedNow() {
        translatedText = translatedCaption.displayText
    }

    private func publishSourceNow() {
        sourceText = sourceCaption.displayText
    }

    private func publishTranslatedIfReadable() {
        let text = translatedCaption.displayText
        if text.hasSentenceBoundary || text.isReadablePartialCaption || !translatedText.isEmpty {
            translatedText = text
        } else if state == .running {
            scheduleTranslatedPublish()
        }
    }

    private func publishSourceIfReadable() {
        let text = sourceCaption.displayText
        if text.hasSentenceBoundary || text.isReadablePartialCaption || !sourceText.isEmpty {
            sourceText = text
        } else if state == .running {
            scheduleSourcePublish()
        }
    }

    private func scheduleClearIfQuiet() {
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                return
            }
            await MainActor.run {
                guard !Task.isCancelled else {
                    return
                }
                self?.sourceCaption.clear()
                self?.translatedCaption.clear()
                self?.sourceText = ""
                self?.translatedText = ""
            }
        }
    }

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter
    }()

    private static func pcm16Level(_ data: Data) -> Double {
        guard data.count >= 2 else {
            return 0
        }
        var sumSquares = 0.0
        var sampleCount = 0
        data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            var index = 0
            while index + 1 < bytes.count {
                let sample = Int16(bitPattern: UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8))
                let normalized = Double(sample) / Double(Int16.max)
                sumSquares += normalized * normalized
                sampleCount += 1
                index += 2
            }
        }
        guard sampleCount > 0 else {
            return 0
        }
        return min(1, sqrt(sumSquares / Double(sampleCount)) * 4)
    }

    private static func appendRealtimeLog(_ line: String) {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/SoundTranslator", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appendingPathComponent("realtime-events.log")
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let data = Data("\(timestamp) \(line)\n".utf8)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: fileURL, options: .atomic)
            }
        } catch {
            // Diagnostics must never interrupt capture or translation.
        }
    }

    private func applyActivationPolicy() {
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
    }

    private func diagnosticScopeDescription() -> String {
        switch currentScope() {
        case .system:
            return "system"
        case let .application(bundleIdentifier, processID):
            return "application:\(bundleIdentifier):\(processID)"
        case nil:
            return "none"
        }
    }

    private static func logSafe(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .prefix(240)
            .description
    }

    private static func shouldLogTranscriptDelta(count: Int, displayText: String) -> Bool {
        count <= 5 || count % 10 == 0 || displayText.hasSentenceBoundary
    }
}

private extension String {
    var hasSentenceBoundary: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else {
            return false
        }
        return [".", "?", "!", "。", "？", "！"].contains(last)
    }

    var isReadablePartialCaption: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        if trimmed.contains(where: { $0.isWhitespace }) {
            return trimmed.count >= 8
        }
        return trimmed.count >= 4
    }
}
