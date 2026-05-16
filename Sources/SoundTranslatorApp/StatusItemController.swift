import AppKit
import Combine
import SoundTranslatorCore

@MainActor
final class StatusItemController {
    var onShowSettings: (() -> Void)?
    var onToggleRunning: (() -> Void)?
    var onQuit: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let viewModel: AppViewModel
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        configure()
        bind()
    }

    private func configure() {
        statusItem.button?.title = "ST"
        rebuildMenu()
    }

    private func bind() {
        viewModel.$state.sink { [weak self] _ in
            self?.rebuildMenu()
        }.store(in: &cancellables)
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let stateItem = NSMenuItem(title: viewModel.state.label, action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())

        let toggleTitle = (viewModel.state == .running || viewModel.state == .connecting) ? "Stop Translation" : "Start Translation"
        menu.addItem(NSMenuItem(title: toggleTitle, action: #selector(toggleRunning), keyEquivalent: "s", target: self))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",", target: self))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q", target: self))
        statusItem.menu = menu
    }

    @objc private func showSettings() {
        onShowSettings?()
    }

    @objc private func toggleRunning() {
        onToggleRunning?()
    }

    @objc private func quit() {
        onQuit?()
    }
}

private extension NSMenuItem {
    convenience init(title: String, action: Selector?, keyEquivalent: String, target: AnyObject) {
        self.init(title: title, action: action, keyEquivalent: keyEquivalent)
        self.target = target
    }
}
