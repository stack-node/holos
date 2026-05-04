import SwiftUI
import AppKit
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        _ = ModuleRegistry.shared
        _ = ExtensionManager.shared
        ExtensionManager.shared.syncSoundModuleWithRegistry()

        LlamaServer.shared.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.updateIcon(state) }
            .store(in: &cancellables)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "brain", accessibilityDescription: "Holos")
        button.image?.isTemplate = true
        button.action = #selector(handleClick)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func updateIcon(_ state: ServerState) {
        let name: String
        switch state {
        case .stopped:  name = "brain"
        case .starting: name = "brain"
        case .running:  name = "brain.head.profile"
        case .failed:   name = "exclamationmark.triangle"
        }
        statusItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Holos")
        statusItem?.button?.image?.isTemplate = true
    }

    @objc private func handleClick() {
        guard let button = statusItem?.button,
              let buttonWindow = button.window else { return }

        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
            return
        }

        let rect = buttonWindow.convertToScreen(button.frame)
        Task { @MainActor in PinManager.shared.toggle(near: rect) }
    }

    private func showContextMenu() {
        guard let button = statusItem?.button,
              let event = NSApp.currentEvent else { return }
        let menu = NSMenu()
        let placeholder = NSMenuItem(title: "Holos", action: nil, keyEquivalent: "")
        placeholder.isEnabled = false
        menu.addItem(placeholder)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Holos", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }
}

@main
struct HolosApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        SwiftUI.Settings { EmptyView() }
    }
}
