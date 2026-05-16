import AppKit
import SwiftUI

@MainActor
final class SubtitleOverlayController {
    private let window: NSPanel
    private let viewModel: AppViewModel

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let width = min(screenFrame.width - 80, 980)
        let height = min(max(screenFrame.height * 0.32, 260), 360)
        let frame = NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.minY + 52,
            width: width,
            height: height
        )
        self.window = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configure()
    }

    func show() {
        window.orderFrontRegardless()
    }

    private func configure() {
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: SubtitleOverlayView(viewModel: viewModel))
    }
}
