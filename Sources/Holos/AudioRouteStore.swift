import CoreAudio
import Foundation

struct AudioElbow: Identifiable, Equatable {
    let id: UUID
    var position: CGPoint
    var label: String

    init(at position: CGPoint, label: String = "Elbow") {
        self.id = UUID()
        self.position = position
        self.label = label
    }
}

struct AudioEqualizerNode: Identifiable, Equatable {
    let id: UUID
    var position: CGPoint
    var label: String

    init(at position: CGPoint, label: String = "Equalizer") {
        self.id = UUID()
        self.position = position
        self.label = label
    }
}

struct AudioSplitterNode: Identifiable, Equatable {
    let id: UUID
    var position: CGPoint
    var label: String
    var leftPercent: Double
    var rightPercent: Double
    var frontPercent: Double
    var backPercent: Double

    init(at position: CGPoint,
         label: String = "Splitter",
         leftPercent: Double = 50,
         rightPercent: Double = 50,
         frontPercent: Double = 50,
         backPercent: Double = 50) {
        self.id = UUID()
        self.position = position
        self.label = label
        self.leftPercent = leftPercent
        self.rightPercent = rightPercent
        self.frontPercent = frontPercent
        self.backPercent = backPercent
    }
}

/// Manages per-app audio routing. On macOS 14.2+ uses AudioRoutingEngine (process taps).
/// On macOS 13 falls back to changing the system default output device.
final class AudioRouteStore: ObservableObject {
    enum GeneralRouteTarget: Equatable {
        case device(AudioOutputDevice)
        case elbow(UUID)
        case splitter(UUID)
    }

    /// bundleID → set of routed deviceIDs
    @Published private(set) var routes: [String: Set<AudioDeviceID>] = [:]
    @Published private(set) var elbows: [UUID: AudioElbow] = [:]
    @Published private(set) var equalizers: [UUID: AudioEqualizerNode] = [:]
    @Published private(set) var splitters: [UUID: AudioSplitterNode] = [:]
    @Published private(set) var appToElbow: [String: UUID] = [:]
    /// Apps may feed more than one splitter (parallel branches).
    @Published private(set) var appToSplitter: [String: Set<UUID>] = [:]
    @Published private(set) var generalRouteTarget: GeneralRouteTarget? = nil
    /// elbowID → ordered list of output devices (deduped by deviceID)
    @Published private(set) var elbowToDevices: [UUID: [AudioOutputDevice]] = [:]
    /// splitterID → ordered list of output devices (deduped by deviceID)
    @Published private(set) var splitterToDevices: [UUID: [AudioOutputDevice]] = [:]

    private var _engine: Any? = nil

    /// Stored in `routes` when only the silence tap is active (must match `AudioRoutingEngine.silenceAnchorDeviceID`).
    private static let silencedRouteDeviceID: AudioDeviceID = .max

    init() {
        if #available(macOS 14.2, *) {
            _engine = AudioRoutingEngine()
        }
    }

    // MARK: - Direct app → device (toggle)

    func setRoute(app: AudioApp, device: AudioOutputDevice) {
        appToElbow.removeValue(forKey: app.bundleIdentifier)
        appToSplitter.removeValue(forKey: app.bundleIdentifier)
        if routes[app.bundleIdentifier]?.contains(device.deviceID) == true {
            doUnroute(app: app, device: device)
        } else {
            doRoute(app: app, device: device)
        }
    }

    func removeRoute(for bundleID: String) {
        if let deviceIDs = routes.removeValue(forKey: bundleID) {
            appToElbow.removeValue(forKey: bundleID)
            appToSplitter.removeValue(forKey: bundleID)
            if #available(macOS 14.2, *), let engine = _engine as? AudioRoutingEngine {
                for id in deviceIDs { engine.unroute(bundleID: bundleID, deviceID: id) }
            }
        }
    }

    func removeAllRoutes() {
        routes.removeAll()
        appToElbow.removeAll()
        appToSplitter.removeAll()
        splitterToDevices.removeAll()
        generalRouteTarget = nil
        if #available(macOS 14.2, *), let engine = _engine as? AudioRoutingEngine {
            engine.unrouteAll()
        }
    }

    // MARK: - Elbow management

    @discardableResult
    func addElbow(at position: CGPoint) -> UUID {
        let elbow = AudioElbow(at: position)
        elbows[elbow.id] = elbow
        return elbow.id
    }

    func moveElbow(id: UUID, to position: CGPoint) {
        elbows[id]?.position = position
    }

    func removeElbow(id: UUID) {
        elbows.removeValue(forKey: id)
        elbowToDevices.removeValue(forKey: id)
        let affected = appToElbow.keys.filter { appToElbow[$0] == id }
        for bundleID in affected {
            appToElbow.removeValue(forKey: bundleID)
            if let deviceIDs = routes.removeValue(forKey: bundleID) {
                if #available(macOS 14.2, *), let engine = _engine as? AudioRoutingEngine {
                    for did in deviceIDs { engine.unroute(bundleID: bundleID, deviceID: did) }
                }
            }
        }
    }

    // MARK: - Equalizer node management (placeholder)

    @discardableResult
    func addEqualizer(at position: CGPoint) -> UUID {
        let node = AudioEqualizerNode(at: position)
        equalizers[node.id] = node
        return node.id
    }

    func moveEqualizer(id: UUID, to position: CGPoint) {
        equalizers[id]?.position = position
    }

    func removeEqualizer(id: UUID) {
        equalizers.removeValue(forKey: id)
    }

    // MARK: - Splitter node management (interactive placeholder)

    @discardableResult
    func addSplitter(at position: CGPoint) -> UUID {
        let node = AudioSplitterNode(at: position)
        splitters[node.id] = node
        return node.id
    }

    func moveSplitter(id: UUID, to position: CGPoint) {
        splitters[id]?.position = position
    }

    func removeSplitter(id: UUID, apps: [AudioApp]) {
        let devices = splitterToDevices[id] ?? []
        splitterToDevices.removeValue(forKey: id)
        splitters.removeValue(forKey: id)
        let byBundle = Dictionary(uniqueKeysWithValues: apps.map { ($0.bundleIdentifier, $0) })
        for bundleID in Array(appToSplitter.keys) {
            guard var set = appToSplitter[bundleID], set.contains(id) else { continue }
            set.remove(id)
            appToSplitter[bundleID] = set.isEmpty ? nil : set
            guard let app = byBundle[bundleID] else { continue }
            for dev in devices {
                doUnroute(app: app, device: dev)
            }
            refreshSilenceAfterGraphChange(app: app)
        }
    }

    func setSplitterLeftPercent(id: UUID, value: Double) {
        let clamped = min(100, max(0, value))
        splitters[id]?.leftPercent = clamped
        splitters[id]?.rightPercent = 100 - clamped
    }

    func setSplitterRightPercent(id: UUID, value: Double) {
        let clamped = min(100, max(0, value))
        splitters[id]?.rightPercent = clamped
        splitters[id]?.leftPercent = 100 - clamped
    }

    func setSplitterFrontPercent(id: UUID, value: Double) {
        let clamped = min(100, max(0, value))
        splitters[id]?.frontPercent = clamped
        splitters[id]?.backPercent = 100 - clamped
    }

    func setSplitterBackPercent(id: UUID, value: Double) {
        let clamped = min(100, max(0, value))
        splitters[id]?.backPercent = clamped
        splitters[id]?.frontPercent = 100 - clamped
    }

    // MARK: - Elbow routing (toggle per device)

    func connectApp(_ app: AudioApp, toElbow elbowID: UUID) {
        appToElbow[app.bundleIdentifier] = elbowID
        appToSplitter.removeValue(forKey: app.bundleIdentifier)
        // Unroute any previous direct routes
        if let deviceIDs = routes.removeValue(forKey: app.bundleIdentifier) {
            if #available(macOS 14.2, *), let engine = _engine as? AudioRoutingEngine {
                for did in deviceIDs { engine.unroute(bundleID: app.bundleIdentifier, deviceID: did) }
            }
        }
        // Route to all devices the elbow currently targets
        for device in elbowToDevices[elbowID] ?? [] {
            doRoute(app: app, device: device)
        }
        refreshSilenceAfterGraphChange(app: app)
    }

    /// Toggles this splitter for the app so one app can drive multiple splitters in parallel.
    func connectApp(_ app: AudioApp, toSplitter splitterID: UUID) {
        appToElbow.removeValue(forKey: app.bundleIdentifier)
        var set = appToSplitter[app.bundleIdentifier] ?? []

        if set.contains(splitterID) {
            set.remove(splitterID)
            if set.isEmpty {
                appToSplitter.removeValue(forKey: app.bundleIdentifier)
            } else {
                appToSplitter[app.bundleIdentifier] = set
            }
            for device in splitterToDevices[splitterID] ?? [] {
                doUnroute(app: app, device: device)
            }
            refreshSilenceAfterGraphChange(app: app)
            return
        }

        if set.isEmpty {
            if let deviceIDs = routes.removeValue(forKey: app.bundleIdentifier) {
                if #available(macOS 14.2, *), let engine = _engine as? AudioRoutingEngine {
                    for did in deviceIDs {
                        engine.unroute(bundleID: app.bundleIdentifier, deviceID: did)
                    }
                }
            }
        }

        set.insert(splitterID)
        appToSplitter[app.bundleIdentifier] = set

        for device in splitterToDevices[splitterID] ?? [] {
            doRoute(app: app, device: device)
        }
        refreshSilenceAfterGraphChange(app: app)
    }

    func setGeneralRoute(toDevice device: AudioOutputDevice, apps: [AudioApp]) {
        generalRouteTarget = .device(device)
        applyGeneralRoute(to: apps)
    }

    func setGeneralRoute(toElbow elbowID: UUID, apps: [AudioApp]) {
        generalRouteTarget = .elbow(elbowID)
        applyGeneralRoute(to: apps)
    }

    func setGeneralRoute(toSplitter splitterID: UUID, apps: [AudioApp]) {
        generalRouteTarget = .splitter(splitterID)
        applyGeneralRoute(to: apps)
    }

    func clearGeneralRoute() {
        generalRouteTarget = nil
    }

    func applyGeneralRoute(to apps: [AudioApp]) {
        guard let target = generalRouteTarget else { return }
        for app in apps where isGeneralCandidate(app) {
            switch target {
            case .device(let device):
                doRoute(app: app, device: device)
            case .elbow(let elbowID):
                connectApp(app, toElbow: elbowID)
            case .splitter(let splitterID):
                connectApp(app, toSplitter: splitterID)
            }
        }
    }

    func disconnectApp(_ app: AudioApp) {
        appToElbow.removeValue(forKey: app.bundleIdentifier)
        appToSplitter.removeValue(forKey: app.bundleIdentifier)
        if let deviceIDs = routes.removeValue(forKey: app.bundleIdentifier) {
            if #available(macOS 14.2, *), let engine = _engine as? AudioRoutingEngine {
                for did in deviceIDs { engine.unroute(bundleID: app.bundleIdentifier, deviceID: did) }
            }
        }
    }

    /// Removes one splitter branch while keeping other splitter / elbow / device routes for this app.
    func disconnectAppFromSplitter(_ app: AudioApp, splitterID: UUID) {
        guard var set = appToSplitter[app.bundleIdentifier], set.contains(splitterID) else { return }
        set.remove(splitterID)
        if set.isEmpty {
            appToSplitter.removeValue(forKey: app.bundleIdentifier)
        } else {
            appToSplitter[app.bundleIdentifier] = set
        }
        for device in splitterToDevices[splitterID] ?? [] {
            doUnroute(app: app, device: device)
        }
        refreshSilenceAfterGraphChange(app: app)
    }

    func connectElbow(_ elbowID: UUID, toDevice device: AudioOutputDevice, apps: [AudioApp]) {
        var devices = elbowToDevices[elbowID] ?? []
        if let idx = devices.firstIndex(where: { $0.deviceID == device.deviceID }) {
            // Toggle off: remove device from elbow and unroute connected apps
            devices.remove(at: idx)
            elbowToDevices[elbowID] = devices
            for app in apps where appToElbow[app.bundleIdentifier] == elbowID {
                doUnroute(app: app, device: device)
            }
            if devices.isEmpty {
                for app in apps where appToElbow[app.bundleIdentifier] == elbowID {
                    refreshSilenceAfterGraphChange(app: app)
                }
            }
        } else {
            // Add device to elbow and route connected apps
            devices.append(device)
            elbowToDevices[elbowID] = devices
            for app in apps where appToElbow[app.bundleIdentifier] == elbowID {
                doRoute(app: app, device: device)
            }
        }
    }

    func connectSplitter(_ splitterID: UUID, toDevice device: AudioOutputDevice, apps: [AudioApp]) {
        var devices = splitterToDevices[splitterID] ?? []
        if let idx = devices.firstIndex(where: { $0.deviceID == device.deviceID }) {
            devices.remove(at: idx)
            splitterToDevices[splitterID] = devices
            for app in apps where appToSplitter[app.bundleIdentifier]?.contains(splitterID) == true {
                doUnroute(app: app, device: device)
                refreshSilenceAfterGraphChange(app: app)
            }
        } else {
            devices.append(device)
            splitterToDevices[splitterID] = devices
            for app in apps where appToSplitter[app.bundleIdentifier]?.contains(splitterID) == true {
                doRoute(app: app, device: device)
            }
        }
    }

    func disconnectElbow(_ elbowID: UUID, fromDevice device: AudioOutputDevice, apps: [AudioApp]) {
        var devices = elbowToDevices[elbowID] ?? []
        guard let idx = devices.firstIndex(where: { $0.deviceID == device.deviceID }) else { return }
        devices.remove(at: idx)
        elbowToDevices[elbowID] = devices
        for app in apps where appToElbow[app.bundleIdentifier] == elbowID {
            doUnroute(app: app, device: device)
        }
    }

    func disconnectAllDevices(fromElbow elbowID: UUID, apps: [AudioApp]) {
        let devices = elbowToDevices[elbowID] ?? []
        guard !devices.isEmpty else { return }
        for device in devices {
            for app in apps where appToElbow[app.bundleIdentifier] == elbowID {
                doUnroute(app: app, device: device)
            }
        }
        elbowToDevices[elbowID] = []
        for app in apps where appToElbow[app.bundleIdentifier] == elbowID {
            refreshSilenceAfterGraphChange(app: app)
        }
    }

    func disconnectDeviceFromAllRoutes(_ device: AudioOutputDevice, apps: [AudioApp]) {
        for app in apps where routes[app.bundleIdentifier]?.contains(device.deviceID) == true {
            doUnroute(app: app, device: device)
        }
        for elbowID in elbowToDevices.keys {
            disconnectElbow(elbowID, fromDevice: device, apps: apps)
        }
        for splitterID in splitterToDevices.keys {
            var devices = splitterToDevices[splitterID] ?? []
            if let idx = devices.firstIndex(where: { $0.deviceID == device.deviceID }) {
                devices.remove(at: idx)
                splitterToDevices[splitterID] = devices
                for app in apps where appToSplitter[app.bundleIdentifier]?.contains(splitterID) == true {
                    doUnroute(app: app, device: device)
                    refreshSilenceAfterGraphChange(app: app)
                }
            }
        }
    }

    // MARK: - Private

    private func unrouteSilenceIfPresent(app: AudioApp) {
        let bid = app.bundleIdentifier
        guard routes[bid]?.contains(Self.silencedRouteDeviceID) == true else { return }
        routes[bid]?.remove(Self.silencedRouteDeviceID)
        if routes[bid]?.isEmpty == true { routes.removeValue(forKey: bid) }
        if #available(macOS 14.2, *), let engine = _engine as? AudioRoutingEngine {
            engine.unroute(bundleID: bid, deviceID: Self.silencedRouteDeviceID)
        }
    }

    /// Tap + mute mix so the app does not play to the default output while staged on an empty splitter/elbow.
    private func doSilenceRoute(app: AudioApp) {
        if #available(macOS 14.2, *), let engine = _engine as? AudioRoutingEngine {
            do {
                try engine.routeSilencingTap(app: app)
                routes[app.bundleIdentifier, default: []].insert(Self.silencedRouteDeviceID)
            } catch {
                // If silence tap fails, leave unrouted (may still hear default output).
            }
        }
    }

    private func refreshSilenceAfterGraphChange(app: AudioApp) {
        let bid = app.bundleIdentifier
        let realDeviceRoutes = (routes[bid] ?? []).filter { $0 != Self.silencedRouteDeviceID }
        if !realDeviceRoutes.isEmpty {
            unrouteSilenceIfPresent(app: app)
            return
        }
        var needsSilence = false
        if let eid = appToElbow[bid], elbowToDevices[eid]?.isEmpty ?? true {
            needsSilence = true
        }
        if !needsSilence {
            for sid in appToSplitter[bid] ?? [] where splitterToDevices[sid]?.isEmpty ?? true {
                needsSilence = true
                break
            }
        }
        if needsSilence {
            doSilenceRoute(app: app)
        } else {
            unrouteSilenceIfPresent(app: app)
        }
    }

    private func doRoute(app: AudioApp, device: AudioOutputDevice) {
        unrouteSilenceIfPresent(app: app)
        if #available(macOS 14.2, *), let engine = _engine as? AudioRoutingEngine {
            do {
                try engine.route(app: app, to: device)
                routes[app.bundleIdentifier, default: []].insert(device.deviceID)
            } catch {
                // Routing failed — don't update UI state
            }
        } else {
            setSystemDefaultOutput(deviceID: device.deviceID)
            routes[app.bundleIdentifier, default: []].insert(device.deviceID)
        }
    }

    private func isGeneralCandidate(_ app: AudioApp) -> Bool {
        appToElbow[app.bundleIdentifier] == nil
            && (appToSplitter[app.bundleIdentifier] ?? []).isEmpty
            && (routes[app.bundleIdentifier]?.isEmpty ?? true)
    }

    private func doUnroute(app: AudioApp, device: AudioOutputDevice) {
        routes[app.bundleIdentifier]?.remove(device.deviceID)
        if routes[app.bundleIdentifier]?.isEmpty == true {
            routes.removeValue(forKey: app.bundleIdentifier)
        }
        if #available(macOS 14.2, *), let engine = _engine as? AudioRoutingEngine {
            engine.unroute(bundleID: app.bundleIdentifier, deviceID: device.deviceID)
        }
    }

    private func setSystemDefaultOutput(deviceID: AudioDeviceID) {
        var id = deviceID
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &id
        )
    }
}
