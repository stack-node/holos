import AudioToolbox
import CoreAudio
import Foundation

// MARK: - Routing engine (macOS 14.2+)

@available(macOS 14.2, *)
final class AudioRoutingEngine {

    enum RoutingError: Error {
        case missingProcessObjectID
        case missingDeviceUID
        case tapCreationFailed(OSStatus)
        case aggregateDeviceCreationFailed(OSStatus)
        case ioProcCreationFailed(OSStatus)
    }

    private struct Session {
        var tapID: AudioObjectID
        var aggregateDeviceID: AudioObjectID
        var ioProcID: AudioDeviceIOProcID?
    }

    // sessions[bundleID][deviceID] = Session
    private var sessions: [String: [AudioDeviceID: Session]] = [:]
    private let ioQueue = DispatchQueue(label: "com.holos.AudioRoutingEngine", qos: .userInitiated)

    /// Used with `AudioRouteStore` so `doUnroute` can tear down silence-only sessions.
    static let silenceAnchorDeviceID: AudioDeviceID = .max

    // MARK: - Public

    /// Taps the app's mix (muting the normal output path) but writes silence to the aggregate so nothing is heard.
    /// Use when the graph assigns an app to a splitter/elbow that has no output devices yet.
    func routeSilencingTap(app: AudioApp) throws {
        guard let processObjectID = app.processObjectID else { throw RoutingError.missingProcessObjectID }
        guard let anchorUID = Self.defaultOutputDeviceUID() else { throw RoutingError.missingDeviceUID }

        // Only replace the silence session so other device routes for this app stay intact.
        unroute(bundleID: app.bundleIdentifier, deviceID: Self.silenceAnchorDeviceID)

        let tapDesc = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        tapDesc.uuid = UUID()
        tapDesc.muteBehavior = .mutedWhenTapped
        tapDesc.isPrivate = true

        var tapID: AudioObjectID = kAudioObjectUnknown
        let tapStatus = AudioHardwareCreateProcessTap(tapDesc, &tapID)
        guard tapStatus == noErr else { throw RoutingError.tapCreationFailed(tapStatus) }

        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey:          "Holos \(app.displayName) → (silenced)",
            kAudioAggregateDeviceUIDKey:           "com.holos.route.silence.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey:     true,
            kAudioAggregateDeviceIsStackedKey:     true,
            kAudioAggregateDeviceTapAutoStartKey:  true,
            kAudioAggregateDeviceMainSubDeviceKey: anchorUID,
            kAudioAggregateDeviceClockDeviceKey:   anchorUID,
            kAudioAggregateDeviceSubDeviceListKey: [[
                kAudioSubDeviceUIDKey:              anchorUID,
                kAudioSubDeviceDriftCompensationKey: false,
            ]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey:              tapDesc.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]

        var aggID: AudioObjectID = kAudioObjectUnknown
        let aggStatus = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &aggID)
        guard aggStatus == noErr else {
            AudioHardwareDestroyProcessTap(tapID)
            throw RoutingError.aggregateDeviceCreationFailed(aggStatus)
        }

        var ioProcID: AudioDeviceIOProcID? = nil
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(
            &ioProcID, aggID, ioQueue
        ) { _, _, _, outOutput, _ in
            AudioRoutingEngine.silenceOutput(outOutput)
        }
        guard procStatus == noErr else {
            AudioHardwareDestroyAggregateDevice(aggID)
            AudioHardwareDestroyProcessTap(tapID)
            throw RoutingError.ioProcCreationFailed(procStatus)
        }

        AudioDeviceStart(aggID, ioProcID)

        if sessions[app.bundleIdentifier] == nil { sessions[app.bundleIdentifier] = [:] }
        sessions[app.bundleIdentifier]![Self.silenceAnchorDeviceID] = Session(tapID: tapID, aggregateDeviceID: aggID, ioProcID: ioProcID)
    }

    func route(app: AudioApp, to device: AudioOutputDevice) throws {
        guard let processObjectID = app.processObjectID else { throw RoutingError.missingProcessObjectID }
        guard let deviceUID = device.uid else { throw RoutingError.missingDeviceUID }

        // Replace any existing session for this specific device
        unroute(bundleID: app.bundleIdentifier, deviceID: device.deviceID)

        // Tap
        let tapDesc = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        tapDesc.uuid = UUID()
        tapDesc.muteBehavior = .mutedWhenTapped
        tapDesc.isPrivate = true

        var tapID: AudioObjectID = kAudioObjectUnknown
        let tapStatus = AudioHardwareCreateProcessTap(tapDesc, &tapID)
        guard tapStatus == noErr else { throw RoutingError.tapCreationFailed(tapStatus) }

        // Private aggregate device wiring tap → physical output
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey:          "Holos \(app.displayName) → \(device.name)",
            kAudioAggregateDeviceUIDKey:           "com.holos.route.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey:     true,
            kAudioAggregateDeviceIsStackedKey:     true,
            kAudioAggregateDeviceTapAutoStartKey:  true,
            kAudioAggregateDeviceMainSubDeviceKey: deviceUID,
            kAudioAggregateDeviceClockDeviceKey:   deviceUID,
            kAudioAggregateDeviceSubDeviceListKey: [[
                kAudioSubDeviceUIDKey:              deviceUID,
                kAudioSubDeviceDriftCompensationKey: false,
            ]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey:              tapDesc.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]

        var aggID: AudioObjectID = kAudioObjectUnknown
        let aggStatus = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &aggID)
        guard aggStatus == noErr else {
            AudioHardwareDestroyProcessTap(tapID)
            throw RoutingError.aggregateDeviceCreationFailed(aggStatus)
        }

        // HAL I/O proc: copy tapped audio to aggregate output
        var ioProcID: AudioDeviceIOProcID? = nil
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(
            &ioProcID, aggID, ioQueue
        ) { _, inInput, _, outOutput, _ in
            AudioRoutingEngine.passthrough(from: inInput, to: outOutput)
        }
        guard procStatus == noErr else {
            AudioHardwareDestroyAggregateDevice(aggID)
            AudioHardwareDestroyProcessTap(tapID)
            throw RoutingError.ioProcCreationFailed(procStatus)
        }

        AudioDeviceStart(aggID, ioProcID)

        if sessions[app.bundleIdentifier] == nil { sessions[app.bundleIdentifier] = [:] }
        sessions[app.bundleIdentifier]![device.deviceID] = Session(tapID: tapID, aggregateDeviceID: aggID, ioProcID: ioProcID)
    }

    func unroute(bundleID: String, deviceID: AudioDeviceID) {
        guard let session = sessions[bundleID]?.removeValue(forKey: deviceID) else { return }
        if sessions[bundleID]?.isEmpty == true { sessions.removeValue(forKey: bundleID) }
        teardown(session)
    }

    func unroute(bundleID: String) {
        guard let deviceSessions = sessions.removeValue(forKey: bundleID) else { return }
        for (_, session) in deviceSessions { teardown(session) }
    }

    func unrouteAll() {
        for bundleID in Array(sessions.keys) { unroute(bundleID: bundleID) }
    }

    // MARK: - Private

    private func teardown(_ session: Session) {
        let tapID = session.tapID
        let aggID = session.aggregateDeviceID
        let procID = session.ioProcID
        ioQueue.async {
            if let procID { AudioDeviceStop(aggID, procID) }
            if let procID { AudioDeviceDestroyIOProcID(aggID, procID) }
            AudioHardwareDestroyAggregateDevice(aggID)
            AudioHardwareDestroyProcessTap(tapID)
        }
    }

    // MARK: - RT-safe audio passthrough

    private static func silenceOutput(_ outOutput: UnsafeMutablePointer<AudioBufferList>?) {
        guard let output = outOutput else { return }
        let outs = UnsafeMutableAudioBufferListPointer(output)
        for outBuf in outs {
            guard let dst = outBuf.mData else { continue }
            memset(dst, 0, Int(outBuf.mDataByteSize))
        }
    }

    private static func defaultOutputDeviceUID() -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID
        ) == noErr, deviceID != 0 else { return nil }

        var uidAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uidSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &uidAddr, 0, nil, &uidSize) == noErr,
              uidSize > 0 else { return nil }

        var unmanaged: Unmanaged<CFString>?
        let st = withUnsafeMutablePointer(to: &unmanaged) { ptr -> OSStatus in
            var mutableSize = uidSize
            return AudioObjectGetPropertyData(deviceID, &uidAddr, 0, nil, &mutableSize, ptr)
        }
        guard st == noErr, let u = unmanaged else { return nil }
        return u.takeRetainedValue() as String
    }

    private static func passthrough(
        from inInput: UnsafePointer<AudioBufferList>?,
        to outOutput: UnsafeMutablePointer<AudioBufferList>?
    ) {
        guard let input = inInput, let output = outOutput else { return }
        var inCopy = input.pointee
        let ins  = UnsafeMutableAudioBufferListPointer(&inCopy)
        let outs = UnsafeMutableAudioBufferListPointer(output)
        for (i, outBuf) in outs.enumerated() {
            guard let dst = outBuf.mData else { continue }
            if i < ins.count, let src = ins[i].mData {
                let bytes = Int(min(ins[i].mDataByteSize, outBuf.mDataByteSize))
                memcpy(dst, src, bytes)
            } else {
                memset(dst, 0, Int(outBuf.mDataByteSize))
            }
        }
    }
}
