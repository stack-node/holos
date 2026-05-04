import AVFoundation
import Accelerate
import AppKit
import CoreGraphics
import CoreMedia
import ScreenCaptureKit

/// Captures **system / app audio** for spectrum analysis (ScreenCaptureKit) with **mic** fallback.
/// Input-only `AVAudioEngine` does not “hear” speaker output, so music playing on the Mac
/// was previously invisible to the visualizer.
final class AudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private let engine = AVAudioEngine()
    private var timer: DispatchSourceTimer?
    private var latestSamples: [Float] = []
    private let lock = NSLock()
    private let maxSampleHistory = 16_384

    private var scStream: SCStream?
    private var usingSystemAudio = false
    private var micTapInstalled = false
    private let audioHandlerQueue = DispatchQueue(label: "holos.screencapture.audio", qos: .userInteractive)
    private let screenHandlerQueue = DispatchQueue(label: "holos.screencapture.screen", qos: .utility)

    let bandCount: Int
    var onBands: (([Double], Double) -> Void)?

    init(bands: Int = 20) {
        self.bandCount = bands
        super.init()
    }

    func start() {
        usingSystemAudio = false
        if #available(macOS 12.3, *) {
            Task { [weak self] in
                await self?.startSystemAudioOrFallback()
            }
        } else {
            startMicEngine()
        }
    }

    func stop() {
        if #available(macOS 12.3, *) {
            scStream?.stopCapture()
            scStream = nil
        }
        timer?.cancel()
        timer = nil
        if micTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            micTapInstalled = false
        }
        if engine.isRunning { engine.stop() }
        lock.lock()
        latestSamples = []
        lock.unlock()
    }

    // MARK: - System audio (ScreenCaptureKit)

    @available(macOS 12.3, *)
    private func startSystemAudioOrFallback() async {
        let access = await MainActor.run { CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() }
        guard access else {
            await MainActor.run { self.startMicEngine() }
            return
        }

        do {
            let content = try await fetchShareableContent()
            guard let display = content.displays.first else {
                await MainActor.run { self.startMicEngine() }
                return
            }

            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale.max)
            config.showsCursor = false
            config.capturesAudio = true
            config.sampleRate = 48_000
            config.channelCount = 2
            config.excludesCurrentProcessAudio = true

            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioHandlerQueue)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: screenHandlerQueue)
            try await stream.startCapture()

            await MainActor.run {
                self.scStream = stream
                self.usingSystemAudio = true
                self.startAnalysisTimer()
            }
        } catch {
            await MainActor.run { self.startMicEngine() }
        }
    }

    @available(macOS 12.3, *)
    private func fetchShareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    // MARK: - Microphone fallback

    private func startMicEngine() {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            startAnalysisTimer()
            return
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
            guard let self, let ch = buf.floatChannelData?[0] else { return }
            let arr = Array(UnsafeBufferPointer(start: ch, count: Int(buf.frameLength)))
            self.pushSamples(arr)
        }
        micTapInstalled = true

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            micTapInstalled = false
        }
        startAnalysisTimer()
    }

    private func pushSamples(_ chunk: [Float]) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        latestSamples.append(contentsOf: chunk)
        if latestSamples.count > maxSampleHistory {
            latestSamples.removeFirst(latestSamples.count - maxSampleHistory)
        }
        lock.unlock()
    }

    private func startAnalysisTimer() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        t.schedule(deadline: .now(), repeating: .milliseconds(33))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        if let floats = Self.extractFloatSamples(from: sampleBuffer) {
            pushSamples(floats)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        if usingSystemAudio {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.scStream = nil
                self.usingSystemAudio = false
                self.startMicEngine()
            }
        }
    }

    private static func extractFloatSamples(from sampleBuffer: CMSampleBuffer) -> [Float]? {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        var length = 0
        var raw: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &raw) == kCMBlockBufferNoErr,
              let base = raw, length > 0 else { return nil }

        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return simpleFloatCopy(base: base, byteCount: length)
        }
        let asbd = asbdPtr.pointee
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        guard isFloat else { return nil }

        let frameCount = Int(CMSampleBufferGetNumSamples(sampleBuffer))
        let channelCount = Int(asbd.mChannelsPerFrame)
        guard frameCount > 0, channelCount > 0 else { return nil }

        let totalFloats = length / MemoryLayout<Float>.size
        let floats = base.withMemoryRebound(to: Float.self, capacity: totalFloats) { ptr in
            Array(UnsafeBufferPointer(start: ptr, count: totalFloats))
        }

        let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        if isNonInterleaved {
            var mono = [Float](repeating: 0, count: frameCount)
            let stride = frameCount
            for ch in 0..<min(channelCount, 2) {
                let plane = Array(floats[stride * ch..<stride * (ch + 1)])
                for i in 0..<frameCount {
                    mono[i] += plane[i]
                }
            }
            let scale = 1.0 / Float(min(channelCount, 2))
            for i in 0..<frameCount { mono[i] *= scale }
            return mono
        }

        if channelCount == 1 { return floats }

        var mono = [Float](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            var s: Float = 0
            for ch in 0..<channelCount {
                s += floats[i * channelCount + ch]
            }
            mono[i] = s / Float(channelCount)
        }
        return mono
    }

    private static func simpleFloatCopy(base: UnsafeMutablePointer<Int8>, byteCount: Int) -> [Float]? {
        let count = byteCount / MemoryLayout<Float>.size
        guard count > 0 else { return nil }
        return base.withMemoryRebound(to: Float.self, capacity: count) { ptr in
            Array(UnsafeBufferPointer(start: ptr, count: count))
        }
    }

    // MARK: - FFT (same as before)

    private static let fftSize = 1024
    private static let log2n = vDSP_Length(10)

    private func tick() {
        lock.lock()
        let samples = latestSamples
        lock.unlock()

        let fftSize = Self.fftSize
        guard samples.count >= fftSize else { return }
        let frame = Array(samples.suffix(fftSize))

        guard let setup = vDSP_create_fftsetup(Self.log2n, FFTRadix(kFFTRadix2)) else { return }
        defer { vDSP_destroy_fftsetup(setup) }

        var windowed = frame
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        var real = [Float](repeating: 0, count: fftSize / 2)
        var imag = [Float](repeating: 0, count: fftSize / 2)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)

        windowed.withUnsafeBufferPointer { wBuf in
            real.withUnsafeMutableBufferPointer { rBuf in
                imag.withUnsafeMutableBufferPointer { iBuf in
                    var split = DSPSplitComplex(realp: rBuf.baseAddress!, imagp: iBuf.baseAddress!)
                    wBuf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { cBuf in
                        vDSP_ctoz(cBuf, 2, &split, 1, vDSP_Length(fftSize / 2))
                    }
                    vDSP_fft_zrip(setup, &split, 1, Self.log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
                }
            }
        }

        let binCount = fftSize / 2
        var bands = [Float](repeating: 0, count: bandCount)
        for i in 0..<bandCount {
            let lo = max(1, Int(powf(Float(binCount), Float(i) / Float(bandCount))))
            let hi = min(binCount, Int(powf(Float(binCount), Float(i + 1) / Float(bandCount))) + 1)
            var sum: Float = 0
            for j in lo..<hi { sum += magnitudes[j] }
            bands[i] = sum / Float(hi - lo)
        }

        for i in 0..<bandCount {
            bands[i] = bands[i] > 0 ? log10f(1.0 + bands[i] * 200.0) / log10f(201.0) : 0
        }

        var maxVal: Float = 0
        vDSP_maxv(bands, 1, &maxVal, vDSP_Length(bandCount))
        if maxVal > 1e-7 {
            var inv = 1.0 / maxVal
            vDSP_vsmul(bands, 1, &inv, &bands, 1, vDSP_Length(bandCount))
        }

        var rms: Float = 0
        frame.withUnsafeBufferPointer { vDSP_rmsqv($0.baseAddress!, 1, &rms, vDSP_Length(fftSize)) }
        let rmsNorm = Double(min(1.0, rms * 40.0))

        let out = bands.map { Double(min(1.0, max(0.0, $0))) }
        DispatchQueue.main.async { [weak self] in self?.onBands?(out, rmsNorm) }
    }
}
