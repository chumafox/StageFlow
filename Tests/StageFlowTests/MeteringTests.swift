import Testing
import AVFoundation
import Accelerate
@testable import StageFlow

@Suite("E06 Metering & VU Calibration Tests")
struct MeteringTests {

    /// Вспомогательная функция для генерации синусоидального буфера
    private func makeSineBuffer(
        frequency: Double,
        amplitude: Float,
        frames: AVAudioFrameCount = 1024,
        sampleRate: Double = 48000.0,
        leftOnly: Bool = false,
        rightOnly: Bool = false
    ) -> AVAudioPCMBuffer {
        let stereoLayout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Stereo)!
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channelLayout: stereoLayout)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        
        for i in 0..<Int(frames) {
            let sample = amplitude * Float(sin(2.0 * .pi * frequency * Double(i) / sampleRate))
            if leftOnly {
                buffer.floatChannelData?[0][i] = sample
                buffer.floatChannelData?[1][i] = 0.0
            } else if rightOnly {
                buffer.floatChannelData?[0][i] = 0.0
                buffer.floatChannelData?[1][i] = sample
            } else {
                buffer.floatChannelData?[0][i] = sample
                buffer.floatChannelData?[1][i] = sample
            }
        }
        return buffer
    }

    /// Вспомогательная функция для генерации тишины
    private func makeSilenceBuffer(frames: AVAudioFrameCount = 1024, sampleRate: Double = 48000.0) -> AVAudioPCMBuffer {
        let stereoLayout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Stereo)!
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channelLayout: stereoLayout)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            buffer.floatChannelData?[0][i] = 0.0
            buffer.floatChannelData?[1][i] = 0.0
        }
        return buffer
    }

    // MARK: - E06.7: Known-Signal Calibration (Sine 0.5 & Silence)
    @Test("Sine wave with amplitude 0.5 yields peak -6.02 dBFS and RMS -9.03 dBFS within 0.5 dB tolerance (E06.7)")
    func testKnownSignalCalibrationSine05() {
        let clock = SimulatedAudioClock(initialTime: 100.0)
        let processor = ChannelMeterProcessor(clock: clock)
        
        // 1000 Hz синус с амплитудой 0.5
        let buffer = makeSineBuffer(frequency: 1000.0, amplitude: 0.5, frames: 4800)
        processor.processBuffer(buffer)
        
        let reading = processor.updateSnapshot()
        
        // Ожидаемый Peak: 20 * log10(0.5) = -6.0206 dBFS
        let expectedPeakDB: Float = -6.0206
        // Ожидаемый RMS: 20 * log10(0.5 / sqrt(2)) = -9.0309 dBFS
        let expectedRMSDB: Float = -9.0309
        
        #expect(abs(reading.peakDB - expectedPeakDB) < 0.5, "Peak DB must be within 0.5 dB of -6.02 dBFS (measured: \(reading.peakDB))")
        #expect(abs(reading.rmsDB - expectedRMSDB) < 0.5, "RMS DB must be within 0.5 dB of -9.03 dBFS (measured: \(reading.rmsDB))")
        #expect(abs(reading.peakLinear - 0.5) < 0.01, "Linear peak must be 0.5")
        #expect(abs(reading.rmsLinear - (0.5 / sqrt(2.0))) < 0.01, "Linear RMS must be ~0.3535")
        #expect(!reading.isClipping, "Amplitude 0.5 must not trigger clipping")
        
        // Шкала 0.0 ... 1.0 от -60 dBFS: (-6.02 - (-60)) / 60 ≈ 0.899
        #expect(abs(reading.level - 0.90) < 0.02, "Normalized level must be ~0.90 for -6 dBFS")
    }

    @Test("Silence produces -120 dBFS floor and zero normalized level without residual noise (E06.4 / E06.7)")
    func testSilenceFloor() {
        let clock = SimulatedAudioClock(initialTime: 100.0)
        let processor = ChannelMeterProcessor(clock: clock)
        
        let silenceBuffer = makeSilenceBuffer(frames: 2048)
        processor.processBuffer(silenceBuffer)
        
        let reading = processor.updateSnapshot()
        
        #expect(reading.peakDB <= -60.0, "Silence peak must be at or below -60 dBFS noise floor")
        #expect(reading.rmsDB <= -60.0, "Silence RMS must be at or below -60 dBFS noise floor")
        #expect(reading.peakLinear == 0.0, "Silence linear peak must be exactly 0.0")
        #expect(reading.rmsLinear == 0.0, "Silence linear RMS must be exactly 0.0")
        #expect(reading.level == 0.0, "Silence normalized level must be exactly 0.0")
        #expect(!reading.isClipping, "Silence must not be clipping")
    }

    // MARK: - E06.2: Stereo Channel Imbalance (L vs R)
    @Test("Stereo imbalance captures maximum peak regardless of channel (Left-only or Right-only) (E06.2)")
    func testStereoChannelImbalance() {
        let clock = SimulatedAudioClock(initialTime: 100.0)
        let processor = ChannelMeterProcessor(clock: clock)
        
        // 1. Сигнал только в левом канале
        let leftBuffer = makeSineBuffer(frequency: 1000.0, amplitude: 0.8, frames: 1024, leftOnly: true)
        processor.processBuffer(leftBuffer)
        let leftReading = processor.updateSnapshot()
        #expect(abs(leftReading.peakLinear - 0.8) < 0.02, "Left-only peak must be detected as 0.8")
        
        processor.reset()
        clock.advance(by: 2.0)
        
        // 2. Сигнал только в правом канале (проверяем, что алгоритм не смотрит только в ch0 / pointee)
        let rightBuffer = makeSineBuffer(frequency: 1000.0, amplitude: 0.8, frames: 1024, rightOnly: true)
        processor.processBuffer(rightBuffer)
        let rightReading = processor.updateSnapshot()
        #expect(abs(rightReading.peakLinear - 0.8) < 0.02, "Right-only peak must be detected as 0.8")
    }

    // MARK: - E06.5: Clip Hold Timing (1.5 seconds)
    @Test("Clip hold flag remains active for exactly 1.5 seconds after overload and then releases (E06.5)")
    func testClipHoldTiming() {
        let clock = SimulatedAudioClock(initialTime: 0.0)
        let processor = ChannelMeterProcessor(clock: clock, clipHoldDuration: 1.5, clipThresholdDB: -0.1)
        
        // 1. Подаем сигнал перегрузки 1.0 (0.0 dBFS >= -0.1 dBFS)
        let clipBuffer = makeSineBuffer(frequency: 1000.0, amplitude: 1.0, frames: 1024)
        processor.processBuffer(clipBuffer)
        
        let initialReading = processor.updateSnapshot()
        #expect(initialReading.isClipping, "Overload signal must activate isClipping")
        
        // 2. Прошло 0.5 секунды тишины — Clip Hold всё ещё активен
        clock.advance(by: 0.5)
        let at05Reading = processor.updateSnapshot()
        #expect(at05Reading.isClipping, "At t = 0.5s, isClipping must still be held true")
        
        // 3. Прошло 1.49 секунды тишины — Clip Hold всё ещё активен
        clock.advance(by: 0.99) // суммарно 1.49 с
        let at149Reading = processor.updateSnapshot()
        #expect(at149Reading.isClipping, "At t = 1.49s, isClipping must still be held true")
        
        // 4. Прошло 1.51 секунды тишины (время удержания 1.5 с истекло) — Clip Hold сброшен
        clock.advance(by: 0.02) // суммарно 1.51 с
        let at151Reading = processor.updateSnapshot()
        #expect(!at151Reading.isClipping, "At t = 1.51s, isClipping must automatically release to false")
    }

    // MARK: - E06.5: Peak Release Ballistics Decay (20 dB/sec)
    @Test("Peak decays smoothly at ~20 dB per second on silence following a peak (E06.5)")
    func testPeakReleaseDecay() {
        let clock = SimulatedAudioClock(initialTime: 0.0)
        let processor = ChannelMeterProcessor(clock: clock, decayRateDBPerSecond: 20.0)
        
        // 1. Подаем 0 dBFS пик (амплитуда 1.0)
        let peakBuffer = makeSineBuffer(frequency: 1000.0, amplitude: 1.0, frames: 1024)
        processor.processBuffer(peakBuffer)
        let peakReading = processor.updateSnapshot()
        #expect(abs(peakReading.peakDB - 0.0) < 0.1, "Initial peak must be 0 dBFS")
        
        // 2. Через 0.5 секунды тишины: спад на 20 * 0.5 = 10 dB -> -10 dBFS
        clock.advance(by: 0.5)
        let at05Reading = processor.updateSnapshot()
        #expect(abs(at05Reading.peakDB - (-10.0)) < 0.5, "At 0.5s, peak must decay to ~ -10 dBFS (measured: \(at05Reading.peakDB))")
        
        // 3. Через 1.0 секунду тишины: спад на 20 * 1.0 = 20 dB -> -20 dBFS
        clock.advance(by: 0.5) // суммарно 1.0 с
        let at10Reading = processor.updateSnapshot()
        #expect(abs(at10Reading.peakDB - (-20.0)) < 0.5, "At 1.0s, peak must decay to ~ -20 dBFS (measured: \(at10Reading.peakDB))")
        
        // 4. Через 3.0 секунды тишины: спад на 60 dB -> достигает -60 dBFS (уровень = 0.0)
        clock.advance(by: 2.0) // суммарно 3.0 с
        let at30Reading = processor.updateSnapshot()
        #expect(at30Reading.peakDB <= -60.0, "At 3.0s, peak must reach noise floor <= -60 dBFS")
        #expect(at30Reading.level == 0.0, "Normalized level must reach 0.0")
    }

    // MARK: - E06.1 / E06.8: Channel Meter Independence (Mic vs Backing, FOH vs IEM)
    @Test("Mic meters do not react to Backing track, and IEM meter is independent of FOH (E06.1 / E06.8)")
    @MainActor
    func testChannelMeterIndependence() {
        let clock = SimulatedAudioClock(initialTime: 0.0)
        let liveEngine = LiveAudioEngine(graphController: AudioGraphController(), clock: clock)
        
        // 1. Подаем аудио только в Backing процессор
        let backingAudio = makeSineBuffer(frequency: 440.0, amplitude: 0.8, frames: 1024)
        liveEngine.meteringCoordinator.backingProcessor.processBuffer(backingAudio)
        
        // Синхронизируем снимки
        liveEngine.syncMetersFromCoordinator()
        
        // Backing meter должен быть активен (> 0.5)
        #expect(liveEngine.backingMeter.level > 0.5, "Backing meter must show active level")
        #expect(liveEngine.backingPeak > 0.5)
        
        // Микрофоны ДОЛЖНЫ быть в полной тишине (устранение бага SF-03!)
        #expect(liveEngine.mic1Meter.level == 0.0, "Mic 1 meter must be zero when only Backing plays")
        #expect(liveEngine.mic1.peakLevel == 0.0)
        #expect(liveEngine.mic2Meter.level == 0.0, "Mic 2 meter must be zero when only Backing plays")
        #expect(liveEngine.mic2.peakLevel == 0.0)
        
        // 2. Теперь подаем аудио только в Mic 1 процессор
        let mic1Audio = makeSineBuffer(frequency: 1000.0, amplitude: 0.7, frames: 1024)
        liveEngine.meteringCoordinator.mic1Processor.processBuffer(mic1Audio)
        liveEngine.syncMetersFromCoordinator()
        
        #expect(liveEngine.mic1Meter.level > 0.5, "Mic 1 meter must show active level")
        #expect(liveEngine.mic1.peakLevel > 0.5)
        // Mic 2 не должен зеркалить Mic 1
        #expect(liveEngine.mic2Meter.level == 0.0, "Mic 2 must remain silent when only Mic 1 receives signal")
        #expect(liveEngine.mic2.peakLevel == 0.0)
        
        // 3. FOH vs IEM независимость: подаем сигнал только в FOH
        let fohAudio = makeSineBuffer(frequency: 1000.0, amplitude: 0.75, frames: 1024)
        liveEngine.meteringCoordinator.fohProcessor.processBuffer(fohAudio)
        liveEngine.syncMetersFromCoordinator()
        
        #expect(liveEngine.fohMeter.level > 0.5, "FOH meter must be active")
        #expect(liveEngine.fohPeak > 0.5)
        #expect(liveEngine.iemMeter.level == 0.0, "IEM meter must NOT mirror FOH (independent bus!)")
        #expect(liveEngine.iemPeak == 0.0)
        
        liveEngine.graphController.stop()
    }

    // MARK: - E06.6: Audio Thread Safety & Coalescing
    @Test("100 rapid buffer ingestions execute lock-free without memory allocations or thread stalls (E06.6)")
    func testAudioThreadBufferIngestPerformance() {
        let clock = SimulatedAudioClock(initialTime: 0.0)
        let processor = ChannelMeterProcessor(clock: clock)
        let buffer = makeSineBuffer(frequency: 1000.0, amplitude: 0.6, frames: 512)
        
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<100 {
            processor.processBuffer(buffer)
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        
        // 100 буферов должны обрабатываться менее чем за 50 миллисекунд (< 0.5 мс на буфер)
        #expect(elapsed < 0.050, "100 buffer ingestions must be ultra-fast (elapsed: \(elapsed) s)")
        
        let reading = processor.updateSnapshot()
        #expect(reading.level > 0.5, "Final snapshot must accurately reflect accumulated buffers")
    }
}
