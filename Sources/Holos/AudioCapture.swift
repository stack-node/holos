import AVFoundation
import Accelerate

final class AudioCapture {
    private let engine = AVAudioEngine()
    private var timer: DispatchSourceTimer?
    private var latestSamples: [Float] = []
    private let lock = NSLock()

    let bandCount: Int
    // Called on the main queue with (bands, rms) both in [0, 1].
    var onBands: (([Double], Double) -> Void)?

    init(bands: Int = 20) {
        self.bandCount = bands
    }

    func start() {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
            guard let self, let ch = buf.floatChannelData?[0] else { return }
            let arr = Array(UnsafeBufferPointer(start: ch, count: Int(buf.frameLength)))
            self.lock.lock()
            self.latestSamples = arr
            self.lock.unlock()
        }

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return
        }

        let t = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        t.schedule(deadline: .now(), repeating: .milliseconds(33))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        lock.lock()
        latestSamples = []
        lock.unlock()
    }

    private static let fftSize = 1024
    private static let log2n  = vDSP_Length(10) // log2(1024)

    private func tick() {
        lock.lock()
        let samples = latestSamples
        lock.unlock()

        let fftSize = Self.fftSize
        guard samples.count >= fftSize else { return }
        let frame = Array(samples.suffix(fftSize))

        guard let setup = vDSP_create_fftsetup(Self.log2n, FFTRadix(kFFTRadix2)) else { return }
        defer { vDSP_destroy_fftsetup(setup) }

        // Hann window
        var windowed = frame
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        // Real FFT via split-complex
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

        // Log-spaced frequency bands
        let binCount = fftSize / 2
        var bands = [Float](repeating: 0, count: bandCount)
        for i in 0..<bandCount {
            let lo = max(1, Int(powf(Float(binCount), Float(i)     / Float(bandCount))))
            let hi = min(binCount, Int(powf(Float(binCount), Float(i + 1) / Float(bandCount))) + 1)
            var sum: Float = 0
            for j in lo..<hi { sum += magnitudes[j] }
            bands[i] = sum / Float(hi - lo)
        }

        // Perceptual log scale
        for i in 0..<bandCount {
            bands[i] = bands[i] > 0 ? log10f(1.0 + bands[i] * 200.0) / log10f(201.0) : 0
        }

        // Normalize to [0, 1]
        var maxVal: Float = 0
        vDSP_maxv(bands, 1, &maxVal, vDSP_Length(bandCount))
        if maxVal > 1e-7 {
            var inv = 1.0 / maxVal
            vDSP_vsmul(bands, 1, &inv, &bands, 1, vDSP_Length(bandCount))
        }

        // RMS loudness
        var rms: Float = 0
        frame.withUnsafeBufferPointer { vDSP_rmsqv($0.baseAddress!, 1, &rms, vDSP_Length(fftSize)) }
        let rmsNorm = Double(min(1.0, rms * 40.0))

        let out = bands.map { Double(min(1.0, max(0.0, $0))) }
        DispatchQueue.main.async { [weak self] in self?.onBands?(out, rmsNorm) }
    }
}
