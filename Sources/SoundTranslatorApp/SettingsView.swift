import SoundTranslatorCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    Divider()
                    apiKeySection
                    languageSection
                    captureSection
                    processSection
                    overlaySection
                    statusSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            controls
        }
        .padding(24)
        .frame(minWidth: 680, minHeight: 640)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Realtime Caption for Mac")
                .font(.system(size: 24, weight: .semibold))
            Text("Realtime translated subtitles for approved Mac audio capture.")
                .foregroundStyle(.secondary)
        }
    }

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OpenAI API Key")
                .font(.headline)
            SecureField("sk-...", text: $viewModel.apiKey)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    viewModel.saveSettings()
                }
            Text("Stored locally in macOS Keychain. It is never written to project files.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var languageSection: some View {
        HStack {
            Text("Translate To")
                .font(.headline)
            Spacer()
            Picker("Translate To", selection: $viewModel.targetLanguage) {
                ForEach(viewModel.languages) { language in
                    Text(language.name).tag(language.id)
                }
            }
            .labelsHidden()
            .frame(width: 220)
            .onChange(of: viewModel.targetLanguage) { _, _ in
                viewModel.saveSettings()
            }
        }
    }

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Audio Source")
                .font(.headline)

            Picker("Audio Source", selection: $viewModel.captureSystemAudio) {
                Text("System output").tag(true)
                Text("Specific app").tag(false)
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.captureSystemAudio) { _, _ in
                viewModel.saveSettings()
            }

            if !viewModel.captureSystemAudio {
                HStack {
                    Picker("App", selection: Binding(
                        get: { viewModel.selectedApplicationID ?? "" },
                        set: { viewModel.selectedApplicationID = $0; viewModel.saveSettings() }
                    )) {
                        Text("Select app").tag("")
                        ForEach(viewModel.applications) { app in
                            Text("\(app.name) (\(app.processID))").tag(app.id)
                        }
                    }
                    Button("Refresh") {
                        Task {
                            await viewModel.refreshApplications()
                        }
                    }
                }
            }

            HStack {
                Text("Captured audio is streamed to OpenAI for translation. Diagnostic input WAV files are saved locally under ~/Library/Logs/SoundTranslator.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Request Permission") {
                    Task {
                        await viewModel.requestCapturePermission()
                    }
                }
                Button("Open Privacy Settings") {
                    viewModel.openScreenAudioPrivacy()
                }
            }
        }
    }

    private var overlaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Overlay")
                .font(.headline)
            HStack {
                Text("Opacity")
                Slider(value: $viewModel.overlayOpacity, in: 0.35...0.95)
                    .onChange(of: viewModel.overlayOpacity) { _, _ in
                        viewModel.saveSettings()
                    }
            }
            HStack {
                Text("Text Size")
                Slider(value: $viewModel.overlayFontSize, in: 18...48)
                    .onChange(of: viewModel.overlayFontSize) { _, _ in
                        viewModel.saveSettings()
                    }
            }
        }
    }

    private var processSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Process")
                .font(.headline)
            Toggle(
                "Show in Dock / Force Quit",
                isOn: Binding(
                    get: { viewModel.showDockIcon },
                    set: { viewModel.setShowDockIcon($0) }
                )
            )
            Text("Turn this on if you want Realtime Caption for Mac to appear outside the menu bar, including in the macOS Force Quit window.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }


    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Status")
                .font(.headline)
            Text(viewModel.state.label)
                .foregroundStyle(viewModel.state == .running ? .green : .primary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Audio: \(viewModel.lastAudioDescription)")
                Text("Packets: \(viewModel.audioPacketCount), Realtime events: \(viewModel.realtimeEventCount)")
                Text("Translated events: \(viewModel.translatedEventCount), Source events: \(viewModel.sourceEventCount)")
                Text("Last event: \(viewModel.lastRealtimeEvent)")
                if let inputAudioDumpPath = viewModel.lastInputAudioDumpPath {
                    Text("Input WAV: \(inputAudioDumpPath)")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if !viewModel.recentRealtimeEvents.isEmpty {
                    Text("Recent events")
                        .fontWeight(.semibold)
                        .padding(.top, 4)
                    ForEach(Array(viewModel.recentRealtimeEvents.enumerated()), id: \.offset) { _, event in
                        Text(event)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Text("~/Library/Logs/SoundTranslator/realtime-events.log")
                        .foregroundStyle(.secondary.opacity(0.75))
                }
                Button("Open Diagnostics Folder") {
                    viewModel.openDiagnosticsFolder()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let lastError = viewModel.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var controls: some View {
        HStack {
            Button("Save") {
                viewModel.saveSettings()
            }
            Button("Translate WAV...") {
                viewModel.selectAndTranslateDebugWAV()
            }
            .disabled(!viewModel.canStart)
            Button("Quit App") {
                Task {
                    await viewModel.quitApplication()
                }
            }
            Spacer()
            Button(viewModel.state == .running || viewModel.state == .connecting ? "Stop" : "Start") {
                Task {
                    await viewModel.toggleRunning()
                }
            }
            .controlSize(.large)
            .keyboardShortcut(.return)
            .disabled(!viewModel.canStart && viewModel.state != .running && viewModel.state != .connecting)
        }
        .frame(minHeight: 34)
    }
}
