import Combine
import CoreAudio
import Foundation

struct AudioOutputDevice: Identifiable, Equatable {
    var id: AudioDeviceID { deviceID }
    let deviceID: AudioDeviceID
    let name: String
    let uid: String?
}

// MARK: - HAL property listener (C callback)

private let kSystemObject: AudioObjectID = 1 // kAudioObjectSystemObject

private func hardwareDevicesPropertyAddress() -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
}

private func hardwareDevicesChanged(
    objectID: AudioObjectID,
    numberAddresses: UInt32,
    addresses: UnsafePointer<AudioObjectPropertyAddress>,
    clientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData else { return noErr }
    let store = Unmanaged<AudioOutputDeviceStore>.fromOpaque(clientData).takeUnretainedValue()
    store.handleHardwareChange()
    return noErr
}

/// Read-only enumeration of output-capable Core Audio devices; refreshes when the HAL device list changes.
final class AudioOutputDeviceStore: ObservableObject {
    @Published private(set) var devices: [AudioOutputDevice] = []

    init() {
        refresh()
        installListener()
    }

    deinit {
        removeListener()
    }

    fileprivate func handleHardwareChange() {
        DispatchQueue.main.async { [weak self] in
            self?.refresh()
        }
    }

    func refresh() {
        let next = Self.fetchOutputDevices()
        if Thread.isMainThread {
            devices = next
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.devices = next
            }
        }
    }

    // MARK: - Listener

    private func installListener() {
        var addr = hardwareDevicesPropertyAddress()
        let status = AudioObjectAddPropertyListener(
            kSystemObject,
            &addr,
            hardwareDevicesChanged,
            Unmanaged.passUnretained(self).toOpaque()
        )
        if status != noErr {
            // Enumeration still works; list may lag until next manual refresh.
        }
    }

    private func removeListener() {
        var addr = hardwareDevicesPropertyAddress()
        _ = AudioObjectRemovePropertyListener(
            kSystemObject,
            &addr,
            hardwareDevicesChanged,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    // MARK: - HAL queries

    private static func fetchOutputDevices() -> [AudioOutputDevice] {
        guard let ids = deviceObjectIDs() else { return [] }
        var result: [AudioOutputDevice] = []
        result.reserveCapacity(ids.count)
        for id in ids where hasOutputChannels(deviceID: id) {
            result.append(makeDevice(deviceID: id))
        }
        result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return result
    }

    private static func deviceObjectIDs() -> [AudioDeviceID]? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(kSystemObject, &addr, 0, nil, &dataSize) == noErr,
              dataSize > 0,
              dataSize % UInt32(MemoryLayout<AudioDeviceID>.size) == 0
        else { return nil }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        let status = ids.withUnsafeMutableBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return kAudioHardwareUnspecifiedError }
            var mutableSize = dataSize
            return AudioObjectGetPropertyData(
                kSystemObject,
                &addr,
                0,
                nil,
                &mutableSize,
                base
            )
        }
        guard status == noErr else { return nil }
        return ids
    }

    private static func hasOutputChannels(deviceID: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &dataSize) == noErr,
              dataSize > 0
        else { return false }

        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }

        var mutableSize = dataSize
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &mutableSize, raw) == noErr else { return false }

        let abl = raw.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        let channels = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
        return channels > 0
    }

    private static func makeDevice(deviceID: AudioDeviceID) -> AudioOutputDevice {
        let nameFromHAL: String? = {
            if let n = copyCFStringProperty(
                objectID: deviceID,
                selector: kAudioObjectPropertyName,
                scope: kAudioObjectPropertyScopeGlobal
            ), !n.isEmpty { return n }
            if let n = copyCFStringProperty(
                objectID: deviceID,
                selector: kAudioDevicePropertyDeviceNameCFString,
                scope: kAudioObjectPropertyScopeGlobal
            ), !n.isEmpty { return n }
            return nil
        }()

        let name = nameFromHAL ?? "Device \(deviceID)"

        let uid = copyCFStringProperty(
            objectID: deviceID,
            selector: kAudioDevicePropertyDeviceUID,
            scope: kAudioObjectPropertyScopeGlobal
        )
        return AudioOutputDevice(deviceID: deviceID, name: name, uid: uid)
    }

    private static func copyCFStringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(objectID, &addr, 0, nil, &dataSize) == noErr,
              dataSize > 0
        else { return nil }

        var unmanaged: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &unmanaged) { ptr -> OSStatus in
            var mutableSize = dataSize
            return AudioObjectGetPropertyData(objectID, &addr, 0, nil, &mutableSize, ptr)
        }
        guard status == noErr, let u = unmanaged else { return nil }
        return u.takeRetainedValue() as String
    }
}
