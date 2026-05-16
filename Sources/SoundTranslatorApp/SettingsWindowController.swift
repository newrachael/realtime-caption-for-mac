import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(viewModel: AppViewModel) {
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 640),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Realtime Caption for Mac"
        window.minSize = NSSize(width: 680, height: 520)
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView(viewModel: viewModel))
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
