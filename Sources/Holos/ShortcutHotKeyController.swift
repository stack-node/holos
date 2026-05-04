import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

/// Carbon `typeHotKeyID` (`'hkID'`) for `GetEventParameter` — not always visible to Swift.
private let kHolosEventParamTypeHotKeyID: EventParamType = {
    let bytes: [UInt8] = [0x68, 0x6B, 0x49, 0x44] // hkID
    let raw = bytes.reduce(UInt32(0)) { ($0 << 8) + UInt32($1) }
    return EventParamType(raw)
}()

/// Installs global Carbon hot keys and dispatches to `ShortcutRegistry` actions.
@MainActor
final class ShortcutHotKeyController {
    static let shared = ShortcutHotKeyController()

    private var eventHandler: EventHandlerRef?
    private var registered: [EventHotKeyRef] = []
    /// `EventHotKeyID.id` (numeric) → Holos shortcut id string
    private var idToShortcut: [UInt32: String] = [:]
    private var nextHotKeyNumericID: UInt32 = 1
    private var cancellables = Set<AnyCancellable>()
    private var hasStarted = false

    private static let hotKeySignature: OSType = {
        "HolS".utf8.reduce(OSType(0)) { acc, b in (acc << 8) + OSType(b) }
    }()

    private init() {
        ShortcutRegistry.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)

        UserShortcutStore.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        installEventHandlerIfNeeded()
        rebuild()
    }

    deinit {
        for r in registered {
            UnregisterEventHotKey(r)
        }
        registered.removeAll()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let err = InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyEventHandlerCallback,
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )
        if err != noErr {
            // Hot keys will not work; app still runs.
        }
    }

    func rebuild() {
        for r in registered {
            UnregisterEventHotKey(r)
        }
        registered.removeAll()
        idToShortcut.removeAll()
        nextHotKeyNumericID = 1

        let reg = ShortcutRegistry.shared
        let visible = reg.visibleDefinitions()
        var used = Set<KeyBinding>()

        for def in visible {
            guard let binding = reg.effectiveBinding(for: def), binding.isValidForRegistration else { continue }
            if used.contains(binding) { continue }
            used.insert(binding)

            let uid = nextHotKeyNumericID
            nextHotKeyNumericID += 1
            idToShortcut[uid] = def.id

            let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: uid)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(binding.keyCode),
                binding.carbonModifiers,
                hotKeyID,
                GetEventDispatcherTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                registered.append(ref)
            } else {
                idToShortcut.removeValue(forKey: uid)
            }
        }
    }

    fileprivate func handleHotKeyEvent(_ event: EventRef) -> OSStatus {
        var hkID = EventHotKeyID()
        let err = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            kHolosEventParamTypeHotKeyID,
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hkID
        )
        guard err == noErr else { return err }

        guard let sid = idToShortcut[hkID.id],
              let definition = ShortcutRegistry.shared.allDefinitionsSnapshot().first(where: { $0.id == sid })
        else { return OSStatus(eventNotHandledErr) }

        guard ShortcutRegistry.shared.isVisible(definition) else { return OSStatus(eventNotHandledErr) }

        switch definition.kind {
        case .toggleMainWindow:
            PinManager.shared.toggleFromGlobalShortcut()
        case .extensionCommand(let extensionId, let action):
            guard let ext = ExtensionManager.shared.extensions.first(where: { $0.id == extensionId }),
                  case .running = ext.runState
            else { break }
            ext.sendCommand(action)
        }

        return noErr
    }
}

/// Carbon calls this without Swift isolation; hop to main actor for Holos state.
private func hotKeyEventHandlerCallback(
    nextHandler: EventHandlerCallRef?,
    theEvent: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData, let theEvent else { return OSStatus(eventNotHandledErr) }
    let controller = Unmanaged<ShortcutHotKeyController>.fromOpaque(userData).takeUnretainedValue()
    return MainActor.assumeIsolated {
        controller.handleHotKeyEvent(theEvent)
    }
}
