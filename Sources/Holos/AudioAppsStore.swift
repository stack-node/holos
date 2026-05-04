import AppKit
import CoreAudio
import Foundation

struct AudioApp: Identifiable, Equatable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let displayName: String
    let trackLine: String?
}

/// Enumerates apps currently outputting audio.
/// macOS 14.2+: CoreAudio process list (all sound apps) merged with MediaRemote track info.
/// macOS 13: MediaRemote fallback (Now Playing apps only).
final class AudioAppsStore: ObservableObject {
    @Published private(set) var apps: [AudioApp] = []

    private var mediaRemoteBundle: CFBundle?
    private var refreshTimer: Timer?
    private var notificationObservers: [NSObjectProtocol] = []

    private typealias GetNowPlayingInfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]?) -> Void) -> Void
    private typealias GetNowPlayingApplicationIsPlayingFn = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias ClientBundleIdFn = @convention(c) (AnyObject?) -> NSString?

    private var getNowPlayingInfo: GetNowPlayingInfoFn?
    private var getNowPlayingApplicationIsPlaying: GetNowPlayingApplicationIsPlayingFn?
    private var clientGetBundleIdentifier: ClientBundleIdFn?

    init() {
        loadMediaRemote()
        startRefreshLoop()
        registerNotifications()
        refresh()
    }

    deinit {
        refreshTimer?.invalidate()
        for o in notificationObservers { NotificationCenter.default.removeObserver(o) }
    }

    func refresh() {
        if #available(macOS 14.2, *) {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                let coreAudioApps = self.fetchAppsViaCoreAudio()
                let trackMap = self.fetchTrackMap()
                let merged = self.merge(coreAudioApps: coreAudioApps, trackMap: trackMap)
                DispatchQueue.main.async { self.apps = merged }
            }
        } else {
            refreshViaMediaRemote()
        }
    }

    // MARK: - CoreAudio (macOS 14.2+)

    @available(macOS 14.2, *)
    private func fetchAppsViaCoreAudio() -> [AudioApp] {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &addr, 0, nil, &dataSize) == noErr, dataSize > 0 else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var processObjects = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(systemObject, &addr, 0, nil, &dataSize, &processObjects) == noErr else { return [] }

        var seen = Set<String>()
        var result: [AudioApp] = []
        for obj in processObjects {
            guard let app = appFromProcessObject(obj), seen.insert(app.bundleIdentifier).inserted else { continue }
            result.append(app)
        }
        return result
    }

    @available(macOS 14.2, *)
    private func appFromProcessObject(_ obj: AudioObjectID) -> AudioApp? {
        var isRunningAddr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunning,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isRunning: UInt32 = 0
        var sz = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(obj, &isRunningAddr, 0, nil, &sz, &isRunning)
        guard isRunning != 0 else { return nil }

        var bundleAddr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfBundleIDRaw: Unmanaged<CFString>? = nil
        var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(obj, &bundleAddr, 0, nil, &bundleSize, &cfBundleIDRaw) == noErr,
              let cfBundleID = cfBundleIDRaw?.takeRetainedValue() else { return nil }
        let bundleID = cfBundleID as String
        guard !bundleID.isEmpty else { return nil }

        let displayName = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName ?? bundleID
        return AudioApp(bundleIdentifier: bundleID, displayName: displayName, trackLine: nil)
    }

    private func merge(coreAudioApps: [AudioApp], trackMap: [String: String]) -> [AudioApp] {
        coreAudioApps.map { app in
            let track = trackMap[app.bundleIdentifier]
            return AudioApp(bundleIdentifier: app.bundleIdentifier, displayName: app.displayName, trackLine: track)
        }
    }

    // MARK: - MediaRemote

    private func loadMediaRemote() {
        let url = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, url as CFURL) else { return }
        mediaRemoteBundle = bundle
        func ptr(_ name: String) -> UnsafeMutableRawPointer? { CFBundleGetFunctionPointerForName(bundle, name as CFString) }
        if let p = ptr("MRMediaRemoteGetNowPlayingInfo") { getNowPlayingInfo = unsafeBitCast(p, to: GetNowPlayingInfoFn.self) }
        if let p = ptr("MRMediaRemoteGetNowPlayingApplicationIsPlaying") { getNowPlayingApplicationIsPlaying = unsafeBitCast(p, to: GetNowPlayingApplicationIsPlayingFn.self) }
        if let p = ptr("MRNowPlayingClientGetBundleIdentifier") { clientGetBundleIdentifier = unsafeBitCast(p, to: ClientBundleIdFn.self) }
    }

    /// Returns a bundle-ID → track-line map for actively playing apps.
    private func fetchTrackMap() -> [String: String] {
        var result: [String: String] = [:]
        if let multi = tryMultiPlayerPaths() {
            for app in multi { if let t = app.trackLine { result[app.bundleIdentifier] = t } }
            return result
        }
        let sem = DispatchSemaphore(value: 0)
        getNowPlayingInfo?(DispatchQueue.global(qos: .userInitiated)) { [weak self] info in
            defer { sem.signal() }
            guard let self, let info, !info.isEmpty, self.isActivelyPlaying(info: info) else { return }
            let bundleId = self.resolveBundleIdentifier(info: info)
            if let bid = bundleId, !bid.isEmpty, let track = self.trackLine(from: info) {
                result[bid] = track
            }
        }
        _ = sem.wait(timeout: .now() + 0.5)
        return result
    }

    private func refreshViaMediaRemote() {
        guard getNowPlayingInfo != nil else {
            DispatchQueue.main.async { [weak self] in self?.apps = [] }
            return
        }
        if let multi = tryMultiPlayerPaths() {
            DispatchQueue.main.async { [weak self] in self?.apps = multi }
            return
        }
        getNowPlayingInfo?(DispatchQueue.global(qos: .userInitiated)) { [weak self] info in
            guard let self else { return }
            let apps = self.buildAppsFromInfo(info)
            DispatchQueue.main.async { self.apps = apps }
        }
    }

    private func buildAppsFromInfo(_ info: [String: Any]?) -> [AudioApp] {
        guard let info, !info.isEmpty, isActivelyPlaying(info: info) else { return [] }
        let bundleId = resolveBundleIdentifier(info: info) ?? guessBundleIdFromRunningMusicApps()
        guard let bundleId, !bundleId.isEmpty else { return [] }
        let track = trackLine(from: info)
        let name = displayName(bundleId: bundleId, info: info)
        return [AudioApp(bundleIdentifier: bundleId, displayName: name, trackLine: track)]
    }

    private func startRefreshLoop() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(refreshTimer!, forMode: .common)
    }

    private func registerNotifications() {
        let names: [Notification.Name] = [
            Notification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
            Notification.Name("kMRMediaRemoteNowPlayingApplicationPlaybackStateDidChangeNotification"),
        ]
        for n in names {
            let o = NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
            notificationObservers.append(o)
        }
    }

    private func isActivelyPlaying(info: [String: Any]) -> Bool {
        if let rate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber, rate.doubleValue > 0 { return true }
        if let playing = info["kMRMediaRemoteNowPlayingInfoIsPlaying"] as? NSNumber, playing.boolValue { return true }
        if let state = info["kMRMediaRemoteNowPlayingInfoPlaybackState"] as? NSNumber, state.intValue == 1 { return true }
        var playing = false
        let sem = DispatchSemaphore(value: 0)
        getNowPlayingApplicationIsPlaying?(DispatchQueue.global(qos: .userInitiated)) { isPlaying in playing = isPlaying; sem.signal() }
        _ = sem.wait(timeout: .now() + 0.15)
        return playing
    }

    private func trackLine(from info: [String: Any]) -> String? {
        let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String
        let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String
        switch (title, artist) {
        case let (t?, a?) where !t.isEmpty && !a.isEmpty: return "\(t) — \(a)"
        case let (t?, _) where !t.isEmpty: return t
        case let (_, a?) where !a.isEmpty: return a
        default: return nil
        }
    }

    private func resolveBundleIdentifier(info: [String: Any]) -> String? {
        let keys = [
            "kMRMediaRemoteNowPlayingInfoBundleIdentifier",
            "kMRMediaRemoteNowPlayingInfoClientIdentifier",
            "kMRMediaRemoteNowPlayingInfoContentSourceIdentifier",
            "kMRMediaRemoteNowPlayingInfoOriginIdentifier",
            "kMRMediaRemoteNowPlayingInfoParentApplicationBundleIdentifier",
            "kMRNowPlayingInfoPropertyIdentifier",
        ]
        for k in keys { if let s = info[k] as? String, !s.isEmpty, s.contains(".") { return s } }
        if let data = info["kMRMediaRemoteNowPlayingInfoClientPropertiesData"] as? Data,
           let bid = bundleIdFromClientPropertiesData(data) { return bid }
        return nil
    }

    private func bundleIdFromClientPropertiesData(_ data: Data) -> String? {
        guard let clientGetBundleIdentifier,
              let cls = NSClassFromString("_MRNowPlayingClientProtobuf") as? NSObject.Type else { return nil }
        let obj: NSObject? = {
            if let o = (cls as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject {
                let sel = NSSelectorFromString("initWithData:")
                if o.responds(to: sel) { return o.perform(sel, with: data)?.takeUnretainedValue() as? NSObject }
            }
            return nil
        }()
        guard let client = obj else { return nil }
        let bid = clientGetBundleIdentifier(client) as String?
        return (bid?.isEmpty == false) ? bid : nil
    }

    private func displayName(bundleId: String, info: [String: Any]) -> String {
        if let s = info["kMRMediaRemoteNowPlayingInfoClientDisplayName"] as? String, !s.isEmpty { return s }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first { return app.localizedName ?? bundleId }
        return bundleId
    }

    private func guessBundleIdFromRunningMusicApps() -> String? {
        let bids = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        return bids.first { id in
            id.contains("music") || id.contains("Spotify") || id.contains("VLC")
                || id.contains("chrome") || id.contains("com.apple.Music") || id.contains("Podcasts")
        } ?? bids.first
    }

    private func tryMultiPlayerPaths() -> [AudioApp]? {
        guard let cls = NSClassFromString("MRNowPlayingRequest") as AnyObject as? NSObject.Type else { return nil }
        for selName in ["allNowPlayingPlayerPaths", "activeNowPlayingPlayerPaths", "nowPlayingPlayerPaths"] {
            let sel = NSSelectorFromString(selName)
            guard cls.responds(to: sel) else { continue }
            guard let result = cls.perform(sel)?.takeUnretainedValue() as? NSArray, result.count > 0 else { continue }
            var out: [AudioApp] = []
            for case let path as NSObject in result {
                if let app = audioAppFromPlayerPath(path) { out.append(app) }
            }
            if !out.isEmpty { return dedupe(out) }
        }
        return nil
    }

    private func audioAppFromPlayerPath(_ path: NSObject) -> AudioApp? {
        let client = (path.value(forKey: "client") as? NSObject) ?? (path.value(forKey: "nowPlayingClient") as? NSObject)
        let bundleId = (client?.value(forKey: "bundleIdentifier") as? String) ?? (client?.value(forKey: "bundleID") as? String)
        guard let bundleId, !bundleId.isEmpty else { return nil }
        let item = path.value(forKey: "nowPlayingItem") as? NSObject
        let info = item?.value(forKey: "nowPlayingInfo") as? [String: Any]
        guard let info, isActivelyPlaying(info: info) else { return nil }
        let track = trackLine(from: info)
        let name = displayName(bundleId: bundleId, info: info)
        return AudioApp(bundleIdentifier: bundleId, displayName: name, trackLine: track)
    }

    private func dedupe(_ apps: [AudioApp]) -> [AudioApp] {
        var seen = Set<String>()
        return apps.filter { seen.insert($0.bundleIdentifier).inserted }
    }
}
