import AppKit
import Foundation
import SoundTranslatorCore

@MainActor
final class AppCoordinator {
    private let viewModel: AppViewModel
    private let statusController: StatusItemController
    private let overlayController: SubtitleOverlayController
    private let settingsController: SettingsWindowController

    init() {
        let viewModel = AppViewModel()
        self.viewModel = viewModel
        self.overlayController = SubtitleOverlayController(viewModel: viewModel)
        self.settingsController = SettingsWindowController(viewModel: viewModel)
        self.statusController = StatusItemController(viewModel: viewModel)

        statusController.onShowSettings = { [weak settingsController] in
            settingsController?.show()
        }
        statusController.onToggleRunning = { [weak viewModel] in
            Task { @MainActor in
                await viewModel?.toggleRunning()
            }
        }
        statusController.onQuit = { [weak viewModel] in
            Task { @MainActor in
                await viewModel?.quitApplication()
            }
        }
    }

    func start() {
        overlayController.show()
        settingsController.show()
    }

    nonisolated func stopImmediately() {
        Task { @MainActor in
            await viewModel.stop()
        }
    }
}
