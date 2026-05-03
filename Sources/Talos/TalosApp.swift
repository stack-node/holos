import SwiftUI
import AppKit
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        LlamaServer.shared.start()

        LlamaServer.shared.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.updateIcon(state) }
            .store(in: &cancellables)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "brain", accessibilityDescription: "Talos")
        button.image?.isTemplate = true
        button.action = #selector(handleClick)
        button.target = self
    }

    private func updateIcon(_ state: ServerState) {
        let name: String
        switch state {
        case .stopped:  name = "brain"
        case .starting: name = "brain"
        case .running:  name = "brain.head.profile"
        case .failed:   name = "exclamationmark.triangle"
        }
        statusItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Talos")
        statusItem?.button?.image?.isTemplate = true
    }

    @objc private func handleClick() {
        guard let button = statusItem?.button,
              let buttonWindow = button.window else { return }
        let rect = buttonWindow.convertToScreen(button.frame)
        Task { @MainActor in PinManager.shared.toggle(near: rect) }
    }
}

@main
struct TalosApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        SwiftUI.Settings { EmptyView() }
    }
}
