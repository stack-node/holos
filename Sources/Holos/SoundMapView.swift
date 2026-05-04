import AppKit
import CoreAudio
import SwiftUI

// MARK: - Sound map

struct SoundMapView: View {
    @StateObject private var outputDevices = AudioOutputDeviceStore()
    @StateObject private var audioApps    = AudioAppsStore()
    @StateObject private var routeStore   = AudioRouteStore()

    @State private var draggingApp:    AudioApp?              = nil
    @State private var draggingGeneral: Bool                  = false
    @State private var draggingElbowPort: UUID?               = nil
    @State private var draggingSplitterPort: UUID?            = nil
    @State private var movingElbow:    UUID?                  = nil
    @State private var movingEqualizer: UUID?                 = nil
    @State private var movingSplitter: UUID?                  = nil
    @State private var movingApp:      String?                = nil
    @State private var movingDevice:   AudioDeviceID?         = nil
    @State private var elbowDragOffset: CGPoint               = .zero
    @State private var equalizerDragOffset: CGPoint           = .zero
    @State private var splitterDragOffset: CGPoint            = .zero
    @State private var appDragOffset:   CGSize                = .zero
    @State private var deviceDragOffset: CGSize               = .zero
    @State private var dragLocation:   CGPoint                = .zero
    @State private var deviceFrames:   [AudioDeviceID: CGRect] = [:]
    @State private var appNodeFrames:  [String: CGRect]        = [:]
    @State private var elbowFrames:    [UUID: CGRect]          = [:]
    @State private var equalizerFrames:[UUID: CGRect]          = [:]
    @State private var splitterFrames: [UUID: CGRect]          = [:]
    @State private var appOffsets:     [String: CGSize]        = [:]
    @State private var deviceOffsets:  [AudioDeviceID: CGSize] = [:]
    @State private var hoveredAppPort: String?                 = nil
    @State private var hoveredDevicePort: AudioDeviceID?       = nil
    @State private var hoveredElbowPort: UUID?                 = nil
    @State private var hoveredSplitterPort: UUID?              = nil
    @State private var monitors:       [Any]                   = []
    @State private var hostWindow:     NSWindow?              = nil

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                SoundMapGridBackground(size: geo.size)

                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(audioApps.apps) { app in
                            ZStack(alignment: .trailing) {
                                SoundMapAudioAppNode(app: app, isDragging: draggingApp?.id == app.id)
                                PortDot(
                                    isConnected: true,
                                    isHot: hoveredAppPort == app.id || draggingApp?.id == app.id || movingApp == app.id
                                )
                                .allowsHitTesting(false)
                                .padding(.trailing, 8)
                            }
                            .offset(appOffsets[app.id] ?? .zero)
                            .anchorPreference(key: NodeAnchorsKey.self, value: .bounds) { ["app_\(app.id)": $0] }
                            .background(GeometryReader { g in
                                Color.clear.preference(key: AppNodeFramesKey.self,
                                    value: [app.id: g.frame(in: .named("soundmap"))])
                            })
                        }
                        SoundMapGeneralInputNode()
                            .anchorPreference(key: NodeAnchorsKey.self, value: .bounds) { ["general_input": $0] }
                            .background(GeometryReader { g in
                                Color.clear.preference(key: AppNodeFramesKey.self,
                                    value: ["general_input": g.frame(in: .named("soundmap"))])
                            })
                        if audioApps.apps.isEmpty {
                            Text("No apps playing audio")
                                .font(.system(.caption))
                                .foregroundStyle(.white.opacity(0.22))
                        }
                    }
                    .frame(maxWidth: 240, alignment: .leading)
                    .padding(.leading, 16)
                    .padding(.top, 12)

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 10) {
                        ForEach(outputDevices.devices) { dev in
                            ZStack(alignment: .leading) {
                                SoundMapOutputDeviceNode(
                                    name: dev.name,
                                    isRouteTarget: routeStore.routes.values.contains(where: { $0.contains(dev.deviceID) })
                                )
                                PortDot(
                                    isConnected: routeStore.routes.values.contains(where: { $0.contains(dev.deviceID) }),
                                    isHot: hoveredDevicePort == dev.deviceID || movingDevice == dev.deviceID
                                )
                                .allowsHitTesting(false)
                                .padding(.leading, 8)
                            }
                            .offset(deviceOffsets[dev.deviceID] ?? .zero)
                            .anchorPreference(key: NodeAnchorsKey.self, value: .bounds) { ["dev_\(dev.id)": $0] }
                            .background(GeometryReader { g in
                                Color.clear.preference(key: DeviceFramesKey.self,
                                    value: [dev.deviceID: g.frame(in: .named("soundmap"))])
                            })
                        }
                        if outputDevices.devices.isEmpty {
                            Text("No output devices found")
                                .font(.system(.caption))
                                .foregroundStyle(.white.opacity(0.22))
                        }
                    }
                    .frame(maxWidth: 240, alignment: .trailing)
                    .padding(.trailing, 16)
                    .padding(.top, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                ForEach(Array(routeStore.elbows.values)) { elbow in
                    SoundMapElbowNode(
                        label: elbow.label,
                        hasApps: routeStore.appToElbow.values.contains(elbow.id),
                        hasDevice: !(routeStore.elbowToDevices[elbow.id]?.isEmpty ?? true),
                        isInputHot: hoveredElbowPort == elbow.id || movingElbow == elbow.id,
                        isOutputHot: hoveredElbowPort == elbow.id || draggingElbowPort == elbow.id || movingElbow == elbow.id
                    )
                    .anchorPreference(key: NodeAnchorsKey.self, value: .bounds) { ["elbow_\(elbow.id)": $0] }
                    .background(GeometryReader { g in
                        Color.clear.preference(key: ElbowFramesKey.self,
                            value: [elbow.id: g.frame(in: .named("soundmap"))])
                    })
                    .position(elbow.position)
                }

                ForEach(Array(routeStore.equalizers.values)) { node in
                    SoundMapEqualizerNode(
                        label: node.label,
                        isHot: movingEqualizer == node.id
                    )
                    .anchorPreference(key: NodeAnchorsKey.self, value: .bounds) { ["eq_\(node.id)": $0] }
                    .background(GeometryReader { g in
                        Color.clear.preference(key: EqualizerFramesKey.self,
                            value: [node.id: g.frame(in: .named("soundmap"))])
                    })
                    .position(node.position)
                }

                ForEach(Array(routeStore.splitters.values)) { node in
                    SoundMapSplitterNode(
                        label: node.label,
                        isHot: movingSplitter == node.id,
                        hasApps: routeStore.appToSplitter.values.contains(where: { $0.contains(node.id) }),
                        hasDevice: !(routeStore.splitterToDevices[node.id]?.isEmpty ?? true),
                        isInputHot: hoveredSplitterPort == node.id || movingSplitter == node.id,
                        isOutputHot: hoveredSplitterPort == node.id || draggingSplitterPort == node.id || movingSplitter == node.id,
                        leftPercent: Binding(
                            get: { routeStore.splitters[node.id]?.leftPercent ?? node.leftPercent },
                            set: { routeStore.setSplitterLeftPercent(id: node.id, value: $0) }
                        ),
                        rightPercent: Binding(
                            get: { routeStore.splitters[node.id]?.rightPercent ?? node.rightPercent },
                            set: { routeStore.setSplitterRightPercent(id: node.id, value: $0) }
                        ),
                        frontPercent: Binding(
                            get: { routeStore.splitters[node.id]?.frontPercent ?? node.frontPercent },
                            set: { routeStore.setSplitterFrontPercent(id: node.id, value: $0) }
                        ),
                        backPercent: Binding(
                            get: { routeStore.splitters[node.id]?.backPercent ?? node.backPercent },
                            set: { routeStore.setSplitterBackPercent(id: node.id, value: $0) }
                        )
                    )
                    .anchorPreference(key: NodeAnchorsKey.self, value: .bounds) { ["splitter_\(node.id)": $0] }
                    .background(GeometryReader { g in
                        Color.clear.preference(key: SplitterFramesKey.self,
                            value: [node.id: g.frame(in: .named("soundmap"))])
                    })
                    .position(node.position)
                }
            }
            .coordinateSpace(name: "soundmap")
            .frame(width: geo.size.width, height: geo.size.height)
            .onPreferenceChange(DeviceFramesKey.self)   { deviceFrames  = $0 }
            .onPreferenceChange(AppNodeFramesKey.self)  { appNodeFrames = $0 }
            .onPreferenceChange(ElbowFramesKey.self)    { elbowFrames   = $0 }
            .onPreferenceChange(EqualizerFramesKey.self) { equalizerFrames = $0 }
            .onPreferenceChange(SplitterFramesKey.self) { splitterFrames = $0 }
            .overlayPreferenceValue(NodeAnchorsKey.self) { prefs in
                GeometryReader { proxy in
                    Canvas { ctx, _ in
                        drawRouteLines(ctx: ctx, proxy: proxy, prefs: prefs)
                        drawGhostLine(ctx: ctx, proxy: proxy, prefs: prefs)
                    }
                }
            }
        }
        .padding(.top, TitleBarLayout.dragStripHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowCapture { hostWindow = $0 })
        .onAppear  { installMonitors() }
        .onDisappear { removeMonitors() }
        .onChange(of: audioApps.apps) { apps in
            routeStore.applyGeneralRoute(to: apps)
        }
    }

    // MARK: - NSEvent monitors (bypass hitTest entirely)

    private func installMonitors() {
        let down = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            let pt = soundmapPoint(event)
            if let eid = elbowOutputPortAt(pt) {
                DispatchQueue.main.async {
                    draggingElbowPort = eid
                    dragLocation = pt
                }
            } else if let app = appOutputPortAt(pt) {
                DispatchQueue.main.async {
                    draggingApp = app
                    dragLocation = pt
                }
            } else if generalInputAt(pt) {
                DispatchQueue.main.async {
                    draggingGeneral = true
                    dragLocation = pt
                }
            } else if let sid = splitterOutputPortAt(pt) {
                DispatchQueue.main.async {
                    draggingSplitterPort = sid
                    dragLocation = pt
                }
            } else if let sid = splitterHeaderAt(pt) {
                let nodePos = routeStore.splitters[sid]?.position ?? pt
                DispatchQueue.main.async {
                    movingSplitter = sid
                    splitterDragOffset = CGPoint(x: nodePos.x - pt.x, y: nodePos.y - pt.y)
                    dragLocation = pt
                }
            } else if let qid = equalizerAt(pt) {
                let nodePos = routeStore.equalizers[qid]?.position ?? pt
                DispatchQueue.main.async {
                    movingEqualizer = qid
                    equalizerDragOffset = CGPoint(x: nodePos.x - pt.x, y: nodePos.y - pt.y)
                    dragLocation = pt
                }
            } else if let app = appAt(pt) {
                let offset = appOffsets[app.id] ?? .zero
                DispatchQueue.main.async {
                    movingApp = app.id
                    appDragOffset = CGSize(width: offset.width - pt.x, height: offset.height - pt.y)
                    dragLocation = pt
                }
            } else if let dev = deviceAt(pt) {
                let offset = deviceOffsets[dev.deviceID] ?? .zero
                DispatchQueue.main.async {
                    movingDevice = dev.deviceID
                    deviceDragOffset = CGSize(width: offset.width - pt.x, height: offset.height - pt.y)
                    dragLocation = pt
                }
            } else if let eid = elbowAt(pt) {
                let elbowPos = routeStore.elbows[eid]?.position ?? pt
                DispatchQueue.main.async {
                    movingElbow = eid
                    elbowDragOffset = CGPoint(x: elbowPos.x - pt.x, y: elbowPos.y - pt.y)
                    dragLocation = pt
                }
            }
            return event
        }
        let drag = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { event in
            let pt = soundmapPoint(event)
            DispatchQueue.main.async { updateHoveredPorts(at: pt) }
            if let eid = movingElbow {
                let newPos = CGPoint(x: pt.x + elbowDragOffset.x, y: pt.y + elbowDragOffset.y)
                DispatchQueue.main.async { routeStore.moveElbow(id: eid, to: newPos) }
            } else if let sid = movingSplitter {
                let newPos = CGPoint(x: pt.x + splitterDragOffset.x, y: pt.y + splitterDragOffset.y)
                DispatchQueue.main.async { routeStore.moveSplitter(id: sid, to: newPos) }
            } else if let qid = movingEqualizer {
                let newPos = CGPoint(x: pt.x + equalizerDragOffset.x, y: pt.y + equalizerDragOffset.y)
                DispatchQueue.main.async { routeStore.moveEqualizer(id: qid, to: newPos) }
            } else if let appID = movingApp {
                let newOffset = CGSize(width: pt.x + appDragOffset.width, height: pt.y + appDragOffset.height)
                DispatchQueue.main.async { appOffsets[appID] = newOffset }
            } else if let devID = movingDevice {
                let newOffset = CGSize(width: pt.x + deviceDragOffset.width, height: pt.y + deviceDragOffset.height)
                DispatchQueue.main.async { deviceOffsets[devID] = newOffset }
            } else if draggingElbowPort != nil || draggingSplitterPort != nil {
                DispatchQueue.main.async { dragLocation = pt }
            } else if draggingApp != nil || draggingGeneral {
                DispatchQueue.main.async { dragLocation = pt }
            }
            return event
        }
        let up = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
            let pt = soundmapPoint(event)
            if let eid = draggingElbowPort {
                if let dev = deviceAt(pt) {
                    DispatchQueue.main.async {
                        routeStore.connectElbow(eid, toDevice: dev, apps: audioApps.apps)
                    }
                }
                DispatchQueue.main.async { draggingElbowPort = nil }
            } else if draggingGeneral {
                if let eid = elbowAt(pt) {
                    DispatchQueue.main.async {
                        routeStore.setGeneralRoute(toElbow: eid, apps: audioApps.apps)
                    }
                } else if let sid = splitterAt(pt) {
                    DispatchQueue.main.async {
                        routeStore.setGeneralRoute(toSplitter: sid, apps: audioApps.apps)
                    }
                } else if let dev = deviceAt(pt) {
                    DispatchQueue.main.async {
                        routeStore.setGeneralRoute(toDevice: dev, apps: audioApps.apps)
                    }
                }
                DispatchQueue.main.async { draggingGeneral = false }
            } else if let sid = draggingSplitterPort {
                if let dev = deviceAt(pt) {
                    DispatchQueue.main.async {
                        routeStore.connectSplitter(sid, toDevice: dev, apps: audioApps.apps)
                    }
                }
                DispatchQueue.main.async { draggingSplitterPort = nil }
            } else if movingSplitter != nil {
                DispatchQueue.main.async { movingSplitter = nil }
            } else if movingEqualizer != nil {
                DispatchQueue.main.async { movingEqualizer = nil }
            } else if movingApp != nil {
                DispatchQueue.main.async { movingApp = nil }
            } else if movingDevice != nil {
                DispatchQueue.main.async { movingDevice = nil }
            } else if let eid = movingElbow {
                if let dev = deviceAt(pt) {
                    DispatchQueue.main.async {
                        routeStore.connectElbow(eid, toDevice: dev, apps: audioApps.apps)
                    }
                }
                DispatchQueue.main.async { movingElbow = nil }
            } else if let app = draggingApp {
                if let eid = elbowAt(pt) {
                    DispatchQueue.main.async { routeStore.connectApp(app, toElbow: eid) }
                } else if let sid = splitterAt(pt) {
                    DispatchQueue.main.async { routeStore.connectApp(app, toSplitter: sid) }
                } else if let dev = deviceAt(pt) {
                    DispatchQueue.main.async { routeStore.setRoute(app: app, device: dev) }
                }
                DispatchQueue.main.async { draggingApp = nil }
            }
            return event
        }
        let rightDown = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
            guard event.window == hostWindow else { return event }
            let pt = soundmapPoint(event)
            if let eid = elbowAt(pt) {
                DispatchQueue.main.async { showElbowMenu(event: event, elbowID: eid) }
                return nil
            } else if generalInputAt(pt) {
                DispatchQueue.main.async { showGeneralMenu(event: event) }
                return nil
            } else if let sid = splitterAt(pt) {
                DispatchQueue.main.async { showSplitterMenu(event: event, splitterID: sid) }
                return nil
            } else if let qid = equalizerAt(pt) {
                DispatchQueue.main.async { showEqualizerMenu(event: event, equalizerID: qid) }
                return nil
            } else if let app = appAt(pt) {
                DispatchQueue.main.async { showAppMenu(event: event, app: app) }
                return nil
            } else if let dev = deviceAt(pt) {
                DispatchQueue.main.async { showDeviceMenu(event: event, device: dev) }
                return nil
            } else if appAt(pt) == nil && deviceAt(pt) == nil {
                showCreateElbowMenu(event: event, position: pt)
                return nil
            }
            return event
        }
        let moved = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
            guard event.window == hostWindow else { return event }
            let pt = soundmapPoint(event)
            DispatchQueue.main.async { updateHoveredPorts(at: pt) }
            return event
        }
        monitors = [down, drag, up, rightDown, moved].compactMap { $0 }
    }

    private func showCreateElbowMenu(event: NSEvent, position: CGPoint) {
        let menu = NSMenu()
        var proxies: [MenuActionProxy] = []
        addMenuItem("Create Elbow", to: menu, proxies: &proxies) {
            routeStore.addElbow(at: position)
        }
        addMenuItem("Create Equalizer Node", to: menu, proxies: &proxies) {
            routeStore.addEqualizer(at: position)
        }
        addMenuItem("Create Splitter Node", to: menu, proxies: &proxies) {
            routeStore.addSplitter(at: position)
        }
        if let cv = (event.window ?? hostWindow)?.contentView {
            NSMenu.popUpContextMenu(menu, with: event, for: cv)
        }
        _ = proxies
    }

    private func showElbowMenu(event: NSEvent, elbowID: UUID) {
        let menu = NSMenu()
        var proxies: [MenuActionProxy] = []
        let connectedDevices = routeStore.elbowToDevices[elbowID] ?? []
        if connectedDevices.isEmpty {
            let empty = NSMenuItem(title: "No connected outputs", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let disconnectSubmenu = NSMenu(title: "Disconnect Output")
            for device in connectedDevices {
                addMenuItem(device.name, to: disconnectSubmenu, proxies: &proxies) {
                    routeStore.disconnectElbow(elbowID, fromDevice: device, apps: audioApps.apps)
                }
            }
            let disconnectItem = NSMenuItem(title: "Disconnect Output", action: nil, keyEquivalent: "")
            menu.setSubmenu(disconnectSubmenu, for: disconnectItem)
            menu.addItem(disconnectItem)

            addMenuItem("Disconnect All Outputs", to: menu, proxies: &proxies) {
                routeStore.disconnectAllDevices(fromElbow: elbowID, apps: audioApps.apps)
            }
        }

        menu.addItem(.separator())
        addMenuItem("Remove Elbow", to: menu, proxies: &proxies) {
            routeStore.removeElbow(id: elbowID)
        }

        if let cv = (event.window ?? hostWindow)?.contentView {
            NSMenu.popUpContextMenu(menu, with: event, for: cv)
        }
        _ = proxies
    }

    private func showEqualizerMenu(event: NSEvent, equalizerID: UUID) {
        let menu = NSMenu()
        var proxies: [MenuActionProxy] = []
        addMenuItem("Remove Equalizer Node", to: menu, proxies: &proxies) {
            routeStore.removeEqualizer(id: equalizerID)
        }
        if let cv = (event.window ?? hostWindow)?.contentView {
            NSMenu.popUpContextMenu(menu, with: event, for: cv)
        }
        _ = proxies
    }

    private func showSplitterMenu(event: NSEvent, splitterID: UUID) {
        let menu = NSMenu()
        var proxies: [MenuActionProxy] = []
        let connectedDevices = routeStore.splitterToDevices[splitterID] ?? []
        if connectedDevices.isEmpty {
            let empty = NSMenuItem(title: "No connected outputs", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let disconnectSubmenu = NSMenu(title: "Disconnect Output")
            for device in connectedDevices {
                addMenuItem(device.name, to: disconnectSubmenu, proxies: &proxies) {
                    routeStore.connectSplitter(splitterID, toDevice: device, apps: audioApps.apps)
                }
            }
            let disconnectItem = NSMenuItem(title: "Disconnect Output", action: nil, keyEquivalent: "")
            menu.setSubmenu(disconnectSubmenu, for: disconnectItem)
            menu.addItem(disconnectItem)
        }

        menu.addItem(.separator())
        addMenuItem("Remove Splitter Node", to: menu, proxies: &proxies) {
            routeStore.removeSplitter(id: splitterID, apps: audioApps.apps)
        }
        if let cv = (event.window ?? hostWindow)?.contentView {
            NSMenu.popUpContextMenu(menu, with: event, for: cv)
        }
        _ = proxies
    }

    private func showGeneralMenu(event: NSEvent) {
        let menu = NSMenu()
        var proxies: [MenuActionProxy] = []
        switch routeStore.generalRouteTarget {
        case .device(let dev):
            let info = NSMenuItem(title: "General -> \(dev.name)", action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        case .elbow(let id):
            let label = routeStore.elbows[id]?.label ?? "Elbow"
            let info = NSMenuItem(title: "General -> \(label)", action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        case .splitter(let id):
            let label = routeStore.splitters[id]?.label ?? "Splitter"
            let info = NSMenuItem(title: "General -> \(label)", action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        case .none:
            let info = NSMenuItem(title: "General route not set", action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        }
        menu.addItem(.separator())
        addMenuItem("Clear General Route", to: menu, proxies: &proxies) {
            routeStore.clearGeneralRoute()
        }
        if let cv = (event.window ?? hostWindow)?.contentView {
            NSMenu.popUpContextMenu(menu, with: event, for: cv)
        }
        _ = proxies
    }

    private func showAppMenu(event: NSEvent, app: AudioApp) {
        let menu = NSMenu()
        var proxies: [MenuActionProxy] = []

        if let elbowID = routeStore.appToElbow[app.bundleIdentifier] {
            addMenuItem("Disconnect from Elbow", to: menu, proxies: &proxies) {
                routeStore.disconnectApp(app)
            }
            if let elbow = routeStore.elbows[elbowID] {
                let info = NSMenuItem(title: "Connected to \(elbow.label)", action: nil, keyEquivalent: "")
                info.isEnabled = false
                menu.addItem(info)
            }
        } else if let splitterSet = routeStore.appToSplitter[app.bundleIdentifier], !splitterSet.isEmpty {
            addMenuItem("Disconnect All Splitters", to: menu, proxies: &proxies) {
                routeStore.disconnectApp(app)
            }
            if splitterSet.count == 1, let onlyID = splitterSet.first, let splitter = routeStore.splitters[onlyID] {
                let info = NSMenuItem(title: "Connected to \(splitter.label)", action: nil, keyEquivalent: "")
                info.isEnabled = false
                menu.addItem(info)
            } else if splitterSet.count > 1 {
                let sub = NSMenu(title: "Connected Splitters")
                for sid in splitterSet.sorted(by: { $0.uuidString < $1.uuidString }) {
                    let title = routeStore.splitters[sid]?.label ?? "Splitter"
                    addMenuItem(title, to: sub, proxies: &proxies) {
                        routeStore.disconnectAppFromSplitter(app, splitterID: sid)
                    }
                }
                let item = NSMenuItem(title: "Disconnect One Splitter…", action: nil, keyEquivalent: "")
                menu.setSubmenu(sub, for: item)
                menu.addItem(item)
            }
        } else {
            let routedIDs = routeStore.routes[app.bundleIdentifier] ?? []
            if routedIDs.isEmpty {
                let empty = NSMenuItem(title: "No direct outputs", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                menu.addItem(empty)
            } else {
                let disconnectSubmenu = NSMenu(title: "Disconnect Output")
                for device in outputDevices.devices where routedIDs.contains(device.deviceID) {
                    addMenuItem(device.name, to: disconnectSubmenu, proxies: &proxies) {
                        routeStore.setRoute(app: app, device: device)
                    }
                }
                let disconnectItem = NSMenuItem(title: "Disconnect Output", action: nil, keyEquivalent: "")
                menu.setSubmenu(disconnectSubmenu, for: disconnectItem)
                menu.addItem(disconnectItem)
            }
        }

        addMenuItem("Remove All Routes for App", to: menu, proxies: &proxies) {
            routeStore.disconnectApp(app)
        }

        if let cv = (event.window ?? hostWindow)?.contentView {
            NSMenu.popUpContextMenu(menu, with: event, for: cv)
        }
        _ = proxies
    }

    private func showDeviceMenu(event: NSEvent, device: AudioOutputDevice) {
        let menu = NSMenu()
        var proxies: [MenuActionProxy] = []

        let directApps = audioApps.apps.filter {
            routeStore.appToElbow[$0.bundleIdentifier] == nil
                && (routeStore.appToSplitter[$0.bundleIdentifier] ?? []).isEmpty
                && (routeStore.routes[$0.bundleIdentifier]?.contains(device.deviceID) == true)
        }
        let elbowLinks = routeStore.elbowToDevices.compactMap { pair -> (UUID, String)? in
            let (eid, devices) = pair
            guard devices.contains(where: { $0.deviceID == device.deviceID }) else { return nil }
            return (eid, routeStore.elbows[eid]?.label ?? "Elbow")
        }
        let splitterLinks = routeStore.splitterToDevices.compactMap { pair -> (UUID, String)? in
            let (sid, devices) = pair
            guard devices.contains(where: { $0.deviceID == device.deviceID }) else { return nil }
            return (sid, routeStore.splitters[sid]?.label ?? "Splitter")
        }

        if directApps.isEmpty && elbowLinks.isEmpty && splitterLinks.isEmpty {
            let empty = NSMenuItem(title: "No links to this output", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            if !directApps.isEmpty {
                let appSubmenu = NSMenu(title: "Disconnect App")
                for app in directApps {
                    addMenuItem(app.displayName, to: appSubmenu, proxies: &proxies) {
                        routeStore.setRoute(app: app, device: device)
                    }
                }
                let appItem = NSMenuItem(title: "Disconnect App", action: nil, keyEquivalent: "")
                menu.setSubmenu(appSubmenu, for: appItem)
                menu.addItem(appItem)
            }

            if !elbowLinks.isEmpty {
                let elbowSubmenu = NSMenu(title: "Disconnect Elbow")
                for (eid, label) in elbowLinks {
                    addMenuItem(label, to: elbowSubmenu, proxies: &proxies) {
                        routeStore.disconnectElbow(eid, fromDevice: device, apps: audioApps.apps)
                    }
                }
                let elbowItem = NSMenuItem(title: "Disconnect Elbow", action: nil, keyEquivalent: "")
                menu.setSubmenu(elbowSubmenu, for: elbowItem)
                menu.addItem(elbowItem)
            }

            if !splitterLinks.isEmpty {
                let splitterSubmenu = NSMenu(title: "Disconnect Splitter")
                for (sid, label) in splitterLinks {
                    addMenuItem(label, to: splitterSubmenu, proxies: &proxies) {
                        routeStore.connectSplitter(sid, toDevice: device, apps: audioApps.apps)
                    }
                }
                let splitterItem = NSMenuItem(title: "Disconnect Splitter", action: nil, keyEquivalent: "")
                menu.setSubmenu(splitterSubmenu, for: splitterItem)
                menu.addItem(splitterItem)
            }
        }

        menu.addItem(.separator())
        addMenuItem("Disconnect All Links to \(device.name)", to: menu, proxies: &proxies) {
            routeStore.disconnectDeviceFromAllRoutes(device, apps: audioApps.apps)
        }

        if let cv = (event.window ?? hostWindow)?.contentView {
            NSMenu.popUpContextMenu(menu, with: event, for: cv)
        }
        _ = proxies
    }

    private func addMenuItem(_ title: String,
                             to menu: NSMenu,
                             proxies: inout [MenuActionProxy],
                             action: @escaping () -> Void) {
        let proxy = MenuActionProxy(action)
        proxies.append(proxy)
        let item = NSMenuItem(title: title, action: #selector(MenuActionProxy.fire(_:)), keyEquivalent: "")
        item.target = proxy
        menu.addItem(item)
    }

    private func updateHoveredPorts(at point: CGPoint) {
        hoveredAppPort = appOutputPortAt(point)?.id
        hoveredDevicePort = deviceGripAt(point)?.deviceID
        hoveredElbowPort = elbowOutputPortAt(point)
        hoveredSplitterPort = splitterOutputPortAt(point)
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
    }

    /// Convert AppKit window coords → SwiftUI "soundmap" coordinate space.
    private func soundmapPoint(_ event: NSEvent) -> CGPoint {
        guard let win = event.window ?? hostWindow,
              let cv  = win.contentView else { return .zero }
        let h  = cv.bounds.height
        let ax = event.locationInWindow.x
        let ay = event.locationInWindow.y
        return CGPoint(x: ax, y: h - ay - TitleBarLayout.dragStripHeight)
    }

    // MARK: - Hit test helpers

    private func appAt(_ pt: CGPoint) -> AudioApp? {
        for app in audioApps.apps {
            if let frame = adjustedAppFrame(for: app.id), frame.contains(pt) { return app }
        }
        return nil
    }

    private func deviceAt(_ pt: CGPoint) -> AudioOutputDevice? {
        for dev in outputDevices.devices {
            if let frame = adjustedDeviceFrame(for: dev.deviceID), frame.contains(pt) { return dev }
        }
        return nil
    }

    private func appGripAt(_ pt: CGPoint) -> AudioApp? {
        let gripWidth: CGFloat = 20
        for app in audioApps.apps {
            guard let frame = adjustedAppFrame(for: app.id) else { continue }
            let gripRect = CGRect(x: frame.maxX - gripWidth, y: frame.minY, width: gripWidth, height: frame.height)
            if gripRect.contains(pt) { return app }
        }
        return nil
    }

    private func deviceGripAt(_ pt: CGPoint) -> AudioOutputDevice? {
        let gripWidth: CGFloat = 20
        for dev in outputDevices.devices {
            guard let frame = adjustedDeviceFrame(for: dev.deviceID) else { continue }
            let gripRect = CGRect(x: frame.minX, y: frame.minY, width: gripWidth, height: frame.height)
            if gripRect.contains(pt) { return dev }
        }
        return nil
    }

    private func elbowAt(_ pt: CGPoint) -> UUID? {
        for elbow in routeStore.elbows.values {
            if let frame = elbowFrames[elbow.id], frame.contains(pt) { return elbow.id }
        }
        return nil
    }

    private func equalizerAt(_ pt: CGPoint) -> UUID? {
        for node in routeStore.equalizers.values {
            if let frame = equalizerFrames[node.id], frame.contains(pt) { return node.id }
        }
        return nil
    }

    private func splitterAt(_ pt: CGPoint) -> UUID? {
        for node in routeStore.splitters.values {
            if let frame = splitterFrames[node.id], frame.contains(pt) { return node.id }
        }
        return nil
    }

    private func splitterHeaderAt(_ pt: CGPoint) -> UUID? {
        for node in routeStore.splitters.values {
            guard let frame = splitterFrames[node.id] else { continue }
            let header = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: 22)
            if header.contains(pt) { return node.id }
        }
        return nil
    }

    private func generalInputAt(_ pt: CGPoint) -> Bool {
        appNodeFrames["general_input"]?.contains(pt) == true
    }

    private func generalOutputPortPoint() -> CGPoint? {
        guard let frame = appNodeFrames["general_input"] else { return nil }
        return CGPoint(x: frame.maxX - 8, y: frame.midY)
    }

    private func elbowOutputPortPoint(for elbowID: UUID) -> CGPoint? {
        guard let frame = elbowFrames[elbowID] else { return nil }
        return CGPoint(x: frame.maxX - 4, y: frame.midY)
    }

    private func elbowInputPortPoint(for elbowID: UUID) -> CGPoint? {
        guard let frame = elbowFrames[elbowID] else { return nil }
        return CGPoint(x: frame.minX + 4, y: frame.midY)
    }

    private func elbowOutputPortAt(_ pt: CGPoint) -> UUID? {
        let hitRadius: CGFloat = 8
        for elbow in routeStore.elbows.values {
            guard let port = elbowOutputPortPoint(for: elbow.id) else { continue }
            let dx = port.x - pt.x
            let dy = port.y - pt.y
            if (dx * dx + dy * dy) <= (hitRadius * hitRadius) {
                return elbow.id
            }
        }
        return nil
    }

    private func appOutputPortPoint(for appID: String) -> CGPoint? {
        guard let frame = adjustedAppFrame(for: appID) else { return nil }
        return CGPoint(x: frame.maxX - 8, y: frame.midY)
    }

    private func appOutputPortAt(_ pt: CGPoint) -> AudioApp? {
        let hitRadius: CGFloat = 8
        for app in audioApps.apps {
            guard let port = appOutputPortPoint(for: app.id) else { continue }
            let dx = port.x - pt.x
            let dy = port.y - pt.y
            if (dx * dx + dy * dy) <= (hitRadius * hitRadius) {
                return app
            }
        }
        return nil
    }

    private func deviceInputPortPoint(for deviceID: AudioDeviceID) -> CGPoint? {
        guard let frame = adjustedDeviceFrame(for: deviceID) else { return nil }
        return CGPoint(x: frame.minX + 8, y: frame.midY)
    }

    private func splitterInputPortPoint(for splitterID: UUID) -> CGPoint? {
        guard let frame = splitterFrames[splitterID] else { return nil }
        return CGPoint(x: frame.minX + 8, y: frame.minY + 11)
    }

    private func splitterOutputPortPoint(for splitterID: UUID) -> CGPoint? {
        guard let frame = splitterFrames[splitterID] else { return nil }
        return CGPoint(x: frame.maxX - 8, y: frame.minY + 11)
    }

    private func splitterOutputPortAt(_ pt: CGPoint) -> UUID? {
        let hitRadius: CGFloat = 8
        for node in routeStore.splitters.values {
            guard let port = splitterOutputPortPoint(for: node.id) else { continue }
            let dx = port.x - pt.x
            let dy = port.y - pt.y
            if (dx * dx + dy * dy) <= (hitRadius * hitRadius) {
                return node.id
            }
        }
        return nil
    }

    private func adjustedAppFrame(for appID: String) -> CGRect? {
        guard let base = appNodeFrames[appID] else { return nil }
        let offset = appOffsets[appID] ?? .zero
        return base.offsetBy(dx: offset.width, dy: offset.height)
    }

    private func adjustedDeviceFrame(for deviceID: AudioDeviceID) -> CGRect? {
        guard let base = deviceFrames[deviceID] else { return nil }
        let offset = deviceOffsets[deviceID] ?? .zero
        return base.offsetBy(dx: offset.width, dy: offset.height)
    }

    // MARK: - Line drawing

    private func drawRouteLines(ctx: GraphicsContext, proxy: GeometryProxy, prefs: [String: Anchor<CGRect>]) {
        let accent = SidebarCategory.sound.color

        // Direct app → device(s) (apps not connected to an elbow)
        for app in audioApps.apps {
            guard routeStore.appToElbow[app.bundleIdentifier] == nil else { continue }
            guard (routeStore.appToSplitter[app.bundleIdentifier] ?? []).isEmpty else { continue }
            guard let appFrom = appOutputPortPoint(for: app.id) else { continue }
            let deviceIDs = routeStore.routes[app.bundleIdentifier]
            if let ids = deviceIDs, !ids.isEmpty {
                for tid in ids {
                    guard let toPoint = deviceInputPortPoint(for: tid) else { continue }
                    strokeRoute(ctx: ctx, from: appFrom,
                                to: toPoint,
                                accent: accent, strong: true)
                }
            } else if let defID = outputDevices.defaultDeviceID,
                      let toPoint = deviceInputPortPoint(for: defID) {
                strokeRoute(ctx: ctx, from: appFrom,
                            to: toPoint,
                            accent: accent, strong: false)
            }
        }

        // General input -> configured stage
        if let start = generalOutputPortPoint() {
            switch routeStore.generalRouteTarget {
            case .device(let device):
                if let end = deviceInputPortPoint(for: device.deviceID) {
                    strokeRoute(ctx: ctx, from: start, to: end, accent: accent, strong: false)
                }
            case .elbow(let id):
                if let end = elbowInputPortPoint(for: id) {
                    strokeRoute(ctx: ctx, from: start, to: end, accent: accent, strong: false)
                }
            case .splitter(let id):
                if let end = splitterInputPortPoint(for: id) {
                    strokeRoute(ctx: ctx, from: start, to: end, accent: accent, strong: false)
                }
            case .none:
                break
            }
        }

        // App → elbow
        for app in audioApps.apps {
            guard let eid = routeStore.appToElbow[app.bundleIdentifier],
                  let elbowAnchor = prefs["elbow_\(eid)"] else { continue }
            guard let fromPoint = appOutputPortPoint(for: app.id) else { continue }
            let elbowRect = proxy[elbowAnchor]
            strokeRoute(ctx: ctx,
                        from: fromPoint,
                        to:   CGPoint(
                            x: elbowInputPortPoint(for: eid)?.x ?? elbowRect.minX,
                            y: elbowInputPortPoint(for: eid)?.y ?? elbowRect.midY
                        ),
                        accent: accent, strong: true)
        }

        // App → splitter(s)
        for app in audioApps.apps {
            guard let fromPoint = appOutputPortPoint(for: app.id) else { continue }
            for sid in routeStore.appToSplitter[app.bundleIdentifier] ?? [] {
                guard let toPoint = splitterInputPortPoint(for: sid) else { continue }
                strokeRoute(ctx: ctx,
                            from: fromPoint,
                            to: toPoint,
                            accent: accent, strong: true)
            }
        }

        // Elbow → device(s)
        for (eid, devices) in routeStore.elbowToDevices {
            guard let elbowAnchor = prefs["elbow_\(eid)"] else { continue }
            let elbowRect = proxy[elbowAnchor]
            let fromPoint = CGPoint(
                x: elbowOutputPortPoint(for: eid)?.x ?? elbowRect.maxX,
                y: elbowOutputPortPoint(for: eid)?.y ?? elbowRect.midY
            )
            for device in devices {
                guard let toPoint = deviceInputPortPoint(for: device.deviceID) else { continue }
                strokeRoute(ctx: ctx,
                            from: fromPoint,
                            to: toPoint,
                            accent: accent, strong: true)
            }
        }

        // Splitter → device(s)
        for (sid, devices) in routeStore.splitterToDevices {
            guard let fromPoint = splitterOutputPortPoint(for: sid) else { continue }
            for device in devices {
                guard let toPoint = deviceInputPortPoint(for: device.deviceID) else { continue }
                strokeRoute(ctx: ctx,
                            from: fromPoint,
                            to: toPoint,
                            accent: accent, strong: true)
            }
        }
    }

    private func strokeRoute(ctx: GraphicsContext,
                              from start: CGPoint, to end: CGPoint,
                              accent: Color, strong: Bool) {
        let path = elbowPath(from: start, to: end)
        ctx.stroke(path, with: .color(accent.opacity(strong ? 0.18 : 0.08)), lineWidth: strong ? 7 : 5)
        let grad = Gradient(colors: [accent.opacity(strong ? 0.9 : 0.55), accent.opacity(strong ? 0.45 : 0.18)])
        ctx.stroke(path, with: .linearGradient(grad, startPoint: start, endPoint: end),
                   lineWidth: strong ? 2 : 1.5)
    }

    private func drawGhostLine(ctx: GraphicsContext, proxy: GeometryProxy, prefs: [String: Anchor<CGRect>]) {
        let accent = SidebarCategory.sound.color
        let end    = dragLocation

        let start: CGPoint
        if let eid = draggingElbowPort, let p = elbowOutputPortPoint(for: eid) {
            start = p
        } else if let sid = draggingSplitterPort, let p = splitterOutputPortPoint(for: sid) {
            start = p
        } else if draggingGeneral, let p = generalOutputPortPoint() {
            start = p
        } else if let app = draggingApp, let anchor = prefs["app_\(app.id)"] {
            let r = proxy[anchor]
            start = CGPoint(
                x: appOutputPortPoint(for: app.id)?.x ?? r.maxX,
                y: appOutputPortPoint(for: app.id)?.y ?? r.midY
            )
        } else {
            return
        }

        let path = elbowPath(from: start, to: end)
        ctx.stroke(path, with: .color(accent.opacity(0.15)), lineWidth: 6)
        ctx.stroke(path, with: .color(accent.opacity(0.7)),
                   style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        let dot = Path(ellipseIn: CGRect(x: end.x - 4, y: end.y - 4, width: 8, height: 8))
        ctx.fill(dot, with: .color(accent.opacity(0.9)))
    }

    private func elbowPath(from start: CGPoint, to end: CGPoint) -> Path {
        let midX = (start.x + end.x) / 2
        var path = Path()
        path.move(to: start)
        path.addLine(to: CGPoint(x: midX, y: start.y))
        path.addLine(to: CGPoint(x: midX, y: end.y))
        path.addLine(to: end)
        return path
    }
}

// MARK: - Preference keys

private struct NodeAnchorsKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct DeviceFramesKey: PreferenceKey {
    static var defaultValue: [AudioDeviceID: CGRect] = [:]
    static func reduce(value: inout [AudioDeviceID: CGRect], nextValue: () -> [AudioDeviceID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct AppNodeFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct ElbowFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct EqualizerFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct SplitterFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}



// MARK: - Grid

private struct SoundMapGridBackground: View {
    var size: CGSize
    private let spacing: CGFloat    = 24
    private let lineOpacity: Double = 0.06

    var body: some View {
        Canvas { ctx, canvasSize in
            let w = canvasSize.width, h = canvasSize.height
            var path = Path()
            var x: CGFloat = 0
            while x <= w { path.move(to: .init(x: x, y: 0)); path.addLine(to: .init(x: x, y: h)); x += spacing }
            var y: CGFloat = 0
            while y <= h { path.move(to: .init(x: 0, y: y)); path.addLine(to: .init(x: w, y: y)); y += spacing }
            ctx.stroke(path, with: .color(.white.opacity(lineOpacity)), lineWidth: 0.5)
        }
        .frame(width: size.width, height: size.height)
        .background(Color(white: 0.04))
    }
}

// MARK: - Nodes

private struct SoundMapAudioAppNode: View {
    var app: AudioApp
    var isDragging: Bool = false

    private var icon: NSImage? {
        NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).first?.icon
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let img = icon {
                    Image(nsImage: img)
                        .resizable().interpolation(.high)
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    Image(systemName: app.trackLine != nil ? "music.note" : "speaker.wave.2.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SidebarCategory.sound.color.opacity(0.75))
                        .frame(width: 20)
                }
                Text(app.displayName)
                    .font(.system(.callout, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if let line = app.trackLine, !line.isEmpty {
                Text(line)
                    .font(.system(.caption2))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(2).multilineTextAlignment(.leading)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 24)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isDragging ? SidebarCategory.sound.color.opacity(0.10) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isDragging ? SidebarCategory.sound.color.opacity(0.45) : Color.white.opacity(0.09),
                              lineWidth: isDragging ? 1 : 0.5)
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct SoundMapGeneralInputNode: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.grid.cross.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SidebarCategory.sound.color.opacity(0.8))
                .frame(width: 20)
            Text("General")
                .font(.system(.callout, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            Spacer(minLength: 8)
            PortDot(isConnected: true, isHot: false)
        }
        .padding(.leading, 12)
        .padding(.trailing, 24)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct SoundMapOutputDeviceNode: View {
    var name: String
    var isRouteTarget: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hifispeaker.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SidebarCategory.sound.color.opacity(isRouteTarget ? 1.0 : 0.75))
            Text(name)
                .font(.system(.callout, weight: .medium))
                .foregroundStyle(.white.opacity(isRouteTarget ? 1.0 : 0.82))
                .lineLimit(1).truncationMode(.tail)
        }
        .padding(.leading, 24)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isRouteTarget ? SidebarCategory.sound.color.opacity(0.12) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isRouteTarget ? SidebarCategory.sound.color.opacity(0.4) : Color.white.opacity(0.09),
                              lineWidth: isRouteTarget ? 1 : 0.5)
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Window capture

private struct WindowCapture: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void
    func makeNSView(context: Context) -> _WindowCaptureView { _WindowCaptureView(onWindow: onWindow) }
    func updateNSView(_ v: _WindowCaptureView, context: Context) {}
}

private final class _WindowCaptureView: NSView {
    let onWindow: (NSWindow?) -> Void
    init(onWindow: @escaping (NSWindow?) -> Void) { self.onWindow = onWindow; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); onWindow(window) }
}

// MARK: - Grip affordance

private struct PortDot: View {
    var isConnected: Bool
    var isHot: Bool

    var body: some View {
        Circle()
            .fill(SidebarCategory.sound.color.opacity(isHot ? 1.0 : (isConnected ? 0.85 : 0.35)))
            .frame(width: 8, height: 8)
    }
}

// MARK: - Elbow node

private struct SoundMapElbowNode: View {
    var label: String
    var hasApps: Bool
    var hasDevice: Bool
    var isInputHot: Bool
    var isOutputHot: Bool

    private var isConnected: Bool { hasApps || hasDevice }

    var body: some View {
        HStack(spacing: 6) {
            PortDot(isConnected: hasApps, isHot: isInputHot)
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SidebarCategory.sound.color.opacity(isConnected ? 1.0 : 0.55))
            Text(label)
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(.white.opacity(isConnected ? 0.9 : 0.55))
                .lineLimit(1)
            PortDot(isConnected: hasDevice, isHot: isOutputHot)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isConnected
                    ? SidebarCategory.sound.color.opacity(0.12)
                    : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isConnected
                    ? SidebarCategory.sound.color.opacity(0.5)
                    : Color.white.opacity(0.12),
                    lineWidth: isConnected ? 1 : 0.5)
        )
    }
}

private struct SoundMapEqualizerNode: View {
    var label: String
    var isHot: Bool

    var body: some View {
        HStack(spacing: 6) {
            PortDot(isConnected: true, isHot: isHot)
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SidebarCategory.sound.color.opacity(0.95))
            Text(label)
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            PortDot(isConnected: true, isHot: isHot)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SidebarCategory.sound.color.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(SidebarCategory.sound.color.opacity(isHot ? 0.75 : 0.5), lineWidth: 1)
        )
    }
}

private struct SoundMapSplitterNode: View {
    var label: String
    var isHot: Bool
    var hasApps: Bool
    var hasDevice: Bool
    var isInputHot: Bool
    var isOutputHot: Bool
    @Binding var leftPercent: Double
    @Binding var rightPercent: Double
    @Binding var frontPercent: Double
    @Binding var backPercent: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                PortDot(isConnected: hasApps, isHot: isInputHot)
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SidebarCategory.sound.color.opacity(0.95))
                Text(label)
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer(minLength: 8)
                PortDot(isConnected: hasDevice, isHot: isOutputHot)
            }

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text("Left \(Int(leftPercent))%")
                        .font(.system(.caption2, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 72, alignment: .leading)
                    Slider(value: $leftPercent, in: 0...100, step: 1)
                        .tint(SidebarCategory.sound.color.opacity(0.95))
                }
                HStack(spacing: 8) {
                    Text("Right \(Int(rightPercent))%")
                        .font(.system(.caption2, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 72, alignment: .leading)
                    Slider(value: $rightPercent, in: 0...100, step: 1)
                        .tint(SidebarCategory.sound.color.opacity(0.95))
                }
                HStack(spacing: 8) {
                    Text("Front \(Int(frontPercent))%")
                        .font(.system(.caption2, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 72, alignment: .leading)
                    Slider(value: $frontPercent, in: 0...100, step: 1)
                        .tint(SidebarCategory.sound.color.opacity(0.95))
                }
                HStack(spacing: 8) {
                    Text("Back \(Int(backPercent))%")
                        .font(.system(.caption2, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 72, alignment: .leading)
                    Slider(value: $backPercent, in: 0...100, step: 1)
                        .tint(SidebarCategory.sound.color.opacity(0.95))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 240)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SidebarCategory.sound.color.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(SidebarCategory.sound.color.opacity(isHot ? 0.75 : 0.5), lineWidth: 1)
        )
    }
}

// MARK: - Menu action proxy

private final class MenuActionProxy: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire(_ sender: Any?) { action() }
}
