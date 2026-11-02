import Testing
import AVFoundation
import Accelerate
@testable import StageFlow

@Suite("E05 Channel Controls & DSP Tests")
struct ChannelControlTests {

    /// Вспомогательная функция для генерации синусоидального стереобуфера
    private func makeSineBuffer(
        format: AVAudioFormat,
        sampleRate: Double,
        frequency: Double,
        amplitude: Float,
        frames: AVAudioFrameCount
    ) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            let sample = amplitude * Float(sin(2.0 * .pi * frequency * Double(i) / sampleRate))
            buffer.floatChannelData?[0][i] = sample
            buffer.floatChannelData?[1][i] = sample
        }
        return buffer
    }

    /// Вспомогательная функция для расчета среднеквадратичного значения (RMS)
    private func computeRMS(buffer: AVAudioPCMBuffer, channel: Int) -> Float {
        guard let data = buffer.floatChannelData?[channel], buffer.frameLength > 0 else { return 0.0 }
        var rms: Float = 0.0
        vDSP_rmsqv(data, 1, &rms, vDSP_Length(buffer.frameLength))
        return rms
    }

    // MARK: - E05.2 / E05.11: Fader Volume Sweep Monotonicity
    @Test("Volume sweep from 0.0 to 1.0 produces monotonically increasing RMS in offline render (E05.2 / E05.11)")
    @MainActor
    func testVolumeSweepMonotonicRMS() throws {
        let graph = AudioGraphController(sampleRate: 48000.0, force4ChannelOutput: true)
        let maxFrames: AVAudioFrameCount = 512
        try graph.engine.enableManualRenderingMode(.offline, format: graph.quadFormat, maximumFrameCount: maxFrames)

        let buffer = makeSineBuffer(
            format: graph.stereoFormat,
            sampleRate: graph.sampleRate,
            frequency: 440.0,
            amplitude: 0.8,
            frames: maxFrames
        )
        graph.playerNode.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        try graph.start()
        graph.playerNode.play()

        let renderBuffer = AVAudioPCMBuffer(pcmFormat: graph.quadFormat, frameCapacity: maxFrames)!
        var previousRMS: Float = -1.0
        let sweepSteps: [Float] = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]

        for step in sweepSteps {
            graph.backingFOHVolume = step
            // Даем CoreAudio 6 циклов (~3000 фреймов) для завершения рампинга громкости
            for _ in 1...6 {
                _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)
            }
            let currentRMS = computeRMS(buffer: renderBuffer, channel: 0)

            if step == 0.0 {
                #expect(currentRMS < 0.0001, "At 0.0 fader volume, output must be silence")
            } else {
                #expect(currentRMS > previousRMS, "RMS at step \(step) must be strictly greater than at \(previousRMS)")
            }
            previousRMS = currentRMS
        }

        graph.playerNode.stop()
        graph.stop()
        graph.engine.disableManualRenderingMode()
    }

    // MARK: - E05.5: Honest Mute with Ramp and Previous Gain Retention
    @Test("Mute completely silences output and un-mute restores previous fader gain (E05.5)")
    @MainActor
    func testMuteHonestSilenceAndRestore() throws {
        let graph = AudioGraphController(sampleRate: 48000.0, force4ChannelOutput: true)
        let maxFrames: AVAudioFrameCount = 512
        try graph.engine.enableManualRenderingMode(.offline, format: graph.quadFormat, maximumFrameCount: maxFrames)

        let buffer = makeSineBuffer(
            format: graph.stereoFormat,
            sampleRate: graph.sampleRate,
            frequency: 440.0,
            amplitude: 0.8,
            frames: maxFrames
        )
        graph.playerNode.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        try graph.start()
        graph.playerNode.play()

        graph.backingFOHVolume = 0.85
        let renderBuffer = AVAudioPCMBuffer(pcmFormat: graph.quadFormat, frameCapacity: maxFrames)!

        // 1. Измеряем начальный неглушенный RMS
        for _ in 1...6 {
            _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)
        }
        let initialRMS = computeRMS(buffer: renderBuffer, channel: 0)
        #expect(initialRMS > 0.4, "Initial playing track must produce audible RMS")

        // 2. Включаем Mute: эффективный gain падает до нуля
        graph.backingIsMuted = true
        #expect(graph.backingFOHVolume == 0.85, "Fader setting must remain preserved during mute")
        #expect(graph.backingFOHGain.outputVolume == 0.0, "Target mixer node outputVolume must be 0.0")

        for _ in 1...6 {
            _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)
        }
        let mutedRMS = computeRMS(buffer: renderBuffer, channel: 0)
        #expect(mutedRMS < 0.0001, "Muted output RMS must be true silence (< 1e-4)")

        // 3. Снимаем Mute: уровень возвращается к исходному значению
        graph.backingIsMuted = false
        #expect(graph.backingFOHGain.outputVolume == 0.85, "Target mixer node outputVolume must restore to 0.85")

        for _ in 1...6 {
            _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)
        }
        let restoredRMS = computeRMS(buffer: renderBuffer, channel: 0)
        #expect(abs(restoredRMS - initialRMS) < 0.02, "Restored RMS must match initial RMS")

        graph.playerNode.stop()
        graph.stop()
        graph.engine.disableManualRenderingMode()
    }

    // MARK: - E05.6: Honest Solo Isolation
    @Test("Solo on Mic 1 isolates it and silences Backing and Mic 2 across both FOH and IEM (E05.6)")
    @MainActor
    func testSoloIsolatesChannel() throws {
        let graph = AudioGraphController(sampleRate: 48000.0, force4ChannelOutput: true)
        let maxFrames: AVAudioFrameCount = 512

        // Подключаем виртуальные плееры для Mic 1 и Mic 2
        let mic1Player = AVAudioPlayerNode()
        let mic2Player = AVAudioPlayerNode()
        graph.engine.attach(mic1Player)
        graph.engine.attach(mic2Player)
        graph.engine.connect(mic1Player, to: graph.mic1InputNode, format: graph.stereoFormat)
        graph.engine.connect(mic2Player, to: graph.mic2InputNode, format: graph.stereoFormat)

        try graph.engine.enableManualRenderingMode(.offline, format: graph.quadFormat, maximumFrameCount: maxFrames)

        let sineBuffer = makeSineBuffer(
            format: graph.stereoFormat,
            sampleRate: graph.sampleRate,
            frequency: 1000.0,
            amplitude: 0.6,
            frames: maxFrames
        )
        graph.playerNode.scheduleBuffer(sineBuffer, at: nil, options: .loops, completionHandler: nil)
        mic1Player.scheduleBuffer(sineBuffer, at: nil, options: .loops, completionHandler: nil)
        mic2Player.scheduleBuffer(sineBuffer, at: nil, options: .loops, completionHandler: nil)

        // Все каналы активны
        graph.backingFOHVolume = 0.8
        graph.backingIEMVolume = 0.8
        graph.mic1FOHVolume = 0.8
        graph.mic1IEMVolume = 0.8
        graph.mic2FOHVolume = 0.8
        graph.mic2IEMVolume = 0.8

        try graph.start()
        graph.playerNode.play()
        mic1Player.play()
        mic2Player.play()

        let renderBuffer = AVAudioPCMBuffer(pcmFormat: graph.quadFormat, frameCapacity: maxFrames)!
        for _ in 1...6 {
            _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)
        }

        // Активируем Solo на Mic 1
        graph.mic1IsSolo = true

        #expect(graph.mic1FOHGain.outputVolume == 0.8)
        #expect(graph.backingFOHGain.outputVolume == 0.0, "Non-solo Backing must be silenced")
        #expect(graph.backingIEMGain.outputVolume == 0.0, "Non-solo Backing IEM must be silenced")
        #expect(graph.mic2FOHGain.outputVolume == 0.0, "Non-solo Mic 2 must be silenced")
        #expect(graph.mic2IEMGain.outputVolume == 0.0, "Non-solo Mic 2 IEM must be silenced")

        for _ in 1...6 {
            _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)
        }
        let soloFOHRMS = computeRMS(buffer: renderBuffer, channel: 0)
        let soloIEMRMS = computeRMS(buffer: renderBuffer, channel: 2)
        #expect(soloFOHRMS > 0.05, "Soloed Mic 1 must sound in FOH")
        #expect(soloIEMRMS > 0.05, "Soloed Mic 1 must sound in IEM")

        // Снимаем Solo: все каналы восстанавливаются
        graph.mic1IsSolo = false
        #expect(graph.backingFOHGain.outputVolume == 0.8)
        #expect(graph.backingIEMGain.outputVolume == 0.8)
        #expect(graph.mic2FOHGain.outputVolume == 0.8)
        #expect(graph.mic2IEMGain.outputVolume == 0.8)

        mic1Player.stop()
        mic2Player.stop()
        graph.playerNode.stop()
        graph.stop()
        graph.engine.disableManualRenderingMode()
    }

    // MARK: - E05.6: Mute Overrides Solo Priority
    @Test("Mute has strict priority over Solo: muted solo channel produces complete silence (E05.6)")
    @MainActor
    func testMuteOverridesSoloPriority() throws {
        let graph = AudioGraphController(sampleRate: 48000.0, force4ChannelOutput: true)
        let maxFrames: AVAudioFrameCount = 512
        try graph.engine.enableManualRenderingMode(.offline, format: graph.quadFormat, maximumFrameCount: maxFrames)

        let buffer = makeSineBuffer(
            format: graph.stereoFormat,
            sampleRate: graph.sampleRate,
            frequency: 1000.0,
            amplitude: 0.8,
            frames: maxFrames
        )
        graph.playerNode.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        try graph.start()
        graph.playerNode.play()

        // Включаем Solo И Mute одновременно на Backing
        graph.backingFOHVolume = 0.8
        graph.backingIsSolo = true
        graph.backingIsMuted = true

        #expect(graph.backingFOHGain.outputVolume == 0.0, "Mute must override Solo to silence the node")
        #expect(graph.backingIEMGain.outputVolume == 0.0)

        let renderBuffer = AVAudioPCMBuffer(pcmFormat: graph.quadFormat, frameCapacity: maxFrames)!
        for _ in 1...6 {
            _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)
        }

        let fohRMS = computeRMS(buffer: renderBuffer, channel: 0)
        let iemRMS = computeRMS(buffer: renderBuffer, channel: 2)
        #expect(fohRMS < 0.0001, "FOH must be completely silent when solo channel is muted")
        #expect(iemRMS < 0.0001, "IEM must be completely silent when solo channel is muted")

        graph.playerNode.stop()
        graph.stop()
        graph.engine.disableManualRenderingMode()
    }

    // MARK: - E05.9: Reverb Send Control & Non-Solo Reverb Silencing
    @Test("Reverb send controls wet amount and non-solo channels have their reverb send silenced (E05.9 / E05.6)")
    @MainActor
    func testReverbSendAndSoloMuting() throws {
        let graph = AudioGraphController(sampleRate: 48000.0, force4ChannelOutput: true)
        let maxFrames: AVAudioFrameCount = 512

        let mic1Player = AVAudioPlayerNode()
        graph.engine.attach(mic1Player)
        graph.engine.connect(mic1Player, to: graph.mic1InputNode, format: graph.stereoFormat)

        try graph.engine.enableManualRenderingMode(.offline, format: graph.quadFormat, maximumFrameCount: maxFrames)

        let buffer = makeSineBuffer(
            format: graph.stereoFormat,
            sampleRate: graph.sampleRate,
            frequency: 1000.0,
            amplitude: 0.8,
            frames: maxFrames
        )
        // 1. Отключаем прямой Dry сигнал и Reverb Send ДО запуска воспроизведения
        graph.mic1FOHVolume = 0.0
        graph.mic1IEMVolume = 0.0
        graph.mic1ReverbSendVolume = 0.0
        #expect(graph.mic1ReverbSend.outputVolume == 0.0)

        mic1Player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        try graph.start()
        mic1Player.play()

        // Reverb Send = 0.0: в ревербератор ничего не поступает, выходной wet = 0
        let renderBuffer = AVAudioPCMBuffer(pcmFormat: graph.quadFormat, frameCapacity: maxFrames)!
        for _ in 1...6 {
            _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)
        }
        let zeroWetRMS = computeRMS(buffer: renderBuffer, channel: 0)
        #expect(zeroWetRMS < 0.0001, "Zero reverb send must produce zero wet output")

        // 2. Reverb Send = 1.0: реверберация появляется
        graph.mic1ReverbSendVolume = 1.0
        #expect(graph.mic1ReverbSend.outputVolume == 1.0)

        for _ in 1...6 {
            _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)
        }
        let activeWetRMS = computeRMS(buffer: renderBuffer, channel: 0)
        #expect(activeWetRMS > 0.005, "Active reverb send must produce audible wet output in FOH")

        // 3. Солирование другого канала (Backing) должно заглушить посыл реверберации от Mic 1
        graph.backingIsSolo = true
        #expect(graph.mic1ReverbSend.outputVolume == 0.0, "Non-solo Mic 1 reverb send must be silenced")

        mic1Player.stop()
        graph.stop()
        graph.engine.disableManualRenderingMode()
    }

    // MARK: - E05.7: EQ Low Cut (80 Hz High-Pass)
    @Test("EQ Low Cut attenuates 40 Hz sub-bass by at least 12 dB while passing 1 kHz transparently (E05.7)")
    @MainActor
    func testEQLowCutFrequencyResponse() throws {
        let graph = AudioGraphController(sampleRate: 48000.0, force4ChannelOutput: true)
        let maxFrames: AVAudioFrameCount = 512

        let mic1Player = AVAudioPlayerNode()
        graph.engine.attach(mic1Player)
        graph.engine.connect(mic1Player, to: graph.mic1InputNode, format: graph.stereoFormat)

        try graph.engine.enableManualRenderingMode(.offline, format: graph.quadFormat, maximumFrameCount: maxFrames)

        graph.mic1FOHVolume = 1.0
        graph.mic1IEMVolume = 0.0
        graph.mic1ReverbSendVolume = 0.0
        // Отключаем компрессор для чистого измерения EQ
        graph.mic1CompressorEnabled = false

        let renderBuffer = AVAudioPCMBuffer(pcmFormat: graph.quadFormat, frameCapacity: maxFrames)!

        // --- Тест 1: 40 Hz сигнал (подавление фильтром) ---
        // Используем 1-секундный буфер (48000 сэмплов = ровно 40 полных периодов 40 Hz),
        // чтобы исключить разрывы и паразитные гармоники на границах зацикливания
        let continuousFrames: AVAudioFrameCount = 48000
        let subBuffer = makeSineBuffer(
            format: graph.stereoFormat,
            sampleRate: graph.sampleRate,
            frequency: 40.0,
            amplitude: 0.8,
            frames: continuousFrames
        )
        mic1Player.scheduleBuffer(subBuffer, at: nil, options: .loops, completionHandler: nil)
        try graph.start()
        mic1Player.play()

        // Без Low-Cut (flat)
        graph.mic1LowCutEnabled = false
        for _ in 1...6 {
            _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)
        }
        let flatSubRMS = computeRMS(buffer: renderBuffer, channel: 0)

        // C Low-Cut (80 Hz highPass active)
        graph.mic1LowCutEnabled = true
        for _ in 1...6 {
            _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)
        }
        let cutSubRMS = computeRMS(buffer: renderBuffer, channel: 0)

        let subAttenuationDB = 20.0 * log10(cutSubRMS / max(flatSubRMS, 1e-9))
        #expect(subAttenuationDB <= -11.5, "80Hz HighPass must attenuate 40Hz sub-bass by ~12 dB (measured: \(subAttenuationDB) dB)")

        mic1Player.stop()

        // --- Тест 2: 1000 Hz сигнал (прозрачность полосы пропускания) ---
        let midBuffer = makeSineBuffer(
            format: graph.stereoFormat,
            sampleRate: graph.sampleRate,
            frequency: 1000.0,
            amplitude: 0.8,
            frames: continuousFrames
        )
        mic1Player.scheduleBuffer(midBuffer, at: nil, options: .loops, completionHandler: nil)
        mic1Player.play()

        graph.mic1LowCutEnabled = false
        for _ in 1...6 {
            _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)
        }
        let flatMidRMS = computeRMS(buffer: renderBuffer, channel: 0)

        graph.mic1LowCutEnabled = true
        for _ in 1...6 {
            _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)
        }
        let cutMidRMS = computeRMS(buffer: renderBuffer, channel: 0)

        let midDiffDB = abs(20.0 * log10(cutMidRMS / max(flatMidRMS, 1e-9)))
        #expect(midDiffDB < 0.5, "1000 Hz passband must not be attenuated by LowCut (diff: \(midDiffDB) dB)")

        mic1Player.stop()
        graph.stop()
        graph.engine.disableManualRenderingMode()
    }

    // MARK: - E05.7: EQ Mid Presence (2.8 kHz Parametric Peak)
    @Test("EQ Mid Gain controls 2.8 kHz presence boost and cut in accordance with gain parameter (E05.7)")
    @MainActor
    func testEQMidGainFrequencyResponse() throws {
        let graph = AudioGraphController(sampleRate: 48000.0, force4ChannelOutput: true)
        let maxFrames: AVAudioFrameCount = 512

        let mic1Player = AVAudioPlayerNode()
        graph.engine.attach(mic1Player)
        graph.engine.connect(mic1Player, to: graph.mic1InputNode, format: graph.stereoFormat)

        try graph.engine.enableManualRenderingMode(.offline, format: graph.quadFormat, maximumFrameCount: maxFrames)

        graph.mic1FOHVolume = 1.0
        graph.mic1IEMVolume = 0.0
        graph.mic1ReverbSendVolume = 0.0
        graph.mic1CompressorEnabled = false

        let presenceBuffer = makeSineBuffer(
            format: graph.stereoFormat,
            sampleRate: graph.sampleRate,
            frequency: 2800.0,
            amplitude: 0.5,
            frames: maxFrames
        )
        mic1Player.scheduleBuffer(presenceBuffer, at: nil, options: .loops, completionHandler: nil)
        try graph.start()
        mic1Player.play()

        let renderBuffer = AVAudioPCMBuffer(pcmFormat: graph.quadFormat, frameCapacity: maxFrames)!

        // Baseline: 0 dB gain
        graph.mic1MidGain = 0.0
        for _ in 1...6 {
            _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)
        }
        let baselineRMS = computeRMS(buffer: renderBuffer, channel: 0)

        // Boost: +6.0 dB gain
        graph.mic1MidGain = 6.0
        for _ in 1...6 {
            _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)
        }
        let boostRMS = computeRMS(buffer: renderBuffer, channel: 0)
        #expect(boostRMS > baselineRMS * 1.5, "Mid gain +6 dB must boost 2.8 kHz presence by at least 1.5x")

        // Cut: -6.0 dB gain
        graph.mic1MidGain = -6.0
        for _ in 1...6 {
            _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)
        }
        let cutRMS = computeRMS(buffer: renderBuffer, channel: 0)
        #expect(cutRMS < baselineRMS * 0.75, "Mid gain -6 dB must attenuate 2.8 kHz presence to < 0.75x")

        mic1Player.stop()
        graph.stop()
        graph.engine.disableManualRenderingMode()
    }

    // MARK: - E05.8: DynamicsProcessor Active Protection
    @Test("DynamicsProcessor compresses high-level peaks when enabled (E05.8)")
    @MainActor
    func testDynamicsProcessorActive() throws {
        let graph = AudioGraphController(sampleRate: 48000.0, force4ChannelOutput: true)
        let maxFrames: AVAudioFrameCount = 512

        let mic1Player = AVAudioPlayerNode()
        graph.engine.attach(mic1Player)
        graph.engine.connect(mic1Player, to: graph.mic1InputNode, format: graph.stereoFormat)

        try graph.engine.enableManualRenderingMode(.offline, format: graph.quadFormat, maximumFrameCount: maxFrames)

        graph.mic1FOHVolume = 1.0
        graph.mic1IEMVolume = 0.0
        graph.mic1ReverbSendVolume = 0.0
        graph.mic1LowCutEnabled = false
        graph.mic1MidGain = 0.0
        graph.mic1HighGain = 0.0

        // По умолчанию компрессор включен
        #expect(graph.mic1CompressorEnabled == true)
        #expect(graph.mic1CompressorNode.bypass == false)

        let loudBuffer = makeSineBuffer(
            format: graph.stereoFormat,
            sampleRate: graph.sampleRate,
            frequency: 1000.0,
            amplitude: 0.9,
            frames: maxFrames
        )
        mic1Player.scheduleBuffer(loudBuffer, at: nil, options: .loops, completionHandler: nil)
        try graph.start()
        mic1Player.play()

        let renderBuffer = AVAudioPCMBuffer(pcmFormat: graph.quadFormat, frameCapacity: maxFrames)!

        // Рендерим с компрессором
        for _ in 1...8 {
            _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)
        }
        let compressedRMS = computeRMS(buffer: renderBuffer, channel: 0)

        // Отключаем компрессор (Bypass)
        graph.mic1CompressorEnabled = false
        #expect(graph.mic1CompressorNode.bypass == true)

        for _ in 1...8 {
            _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)
        }
        let uncompressedRMS = computeRMS(buffer: renderBuffer, channel: 0)

        #expect(compressedRMS < uncompressedRMS, "Active dynamics processor must reduce RMS on high-amplitude input")

        mic1Player.stop()
        graph.stop()
        graph.engine.disableManualRenderingMode()
    }

    // MARK: - E05.10 / E05.11: Rapid Parameter Sweeps (Stress & Anti-Click Ramping)
    @Test("100 rapid consecutive parameter sweeps execute without crashes or numerical instabilities (E05.10 / E05.11)")
    @MainActor
    func testRapidParameterSweeps100Cycles() throws {
        let graph = AudioGraphController(sampleRate: 48000.0, force4ChannelOutput: true)
        let maxFrames: AVAudioFrameCount = 512
        try graph.engine.enableManualRenderingMode(.offline, format: graph.quadFormat, maximumFrameCount: maxFrames)

        let buffer = makeSineBuffer(
            format: graph.stereoFormat,
            sampleRate: graph.sampleRate,
            frequency: 440.0,
            amplitude: 0.8,
            frames: maxFrames
        )
        graph.playerNode.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        try graph.start()
        graph.playerNode.play()

        let renderBuffer = AVAudioPCMBuffer(pcmFormat: graph.quadFormat, frameCapacity: maxFrames)!

        for cycle in 0..<100 {
            let volume = Float(cycle % 10) / 10.0
            graph.backingFOHVolume = volume
            graph.backingIEMVolume = 1.0 - volume
            graph.mic1FOHVolume = volume * 0.8
            graph.mic1ReverbSendVolume = volume * 0.5
            graph.backingIsMuted = (cycle % 7 == 0)
            graph.mic1IsSolo = (cycle % 11 == 0)
            graph.mic1MidGain = Float((cycle % 12) - 6)

            _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)

            guard let ch0 = renderBuffer.floatChannelData?[0] else {
                Issue.record("Missing float channel data in cycle \(cycle)")
                break
            }
            // Проверяем отсутствие NaN и бесконечностей
            for i in stride(from: 0, to: Int(maxFrames), by: 32) {
                #expect(!ch0[i].isNaN, "Render buffer sample at cycle \(cycle) frame \(i) must not be NaN")
                #expect(!ch0[i].isInfinite, "Render buffer sample at cycle \(cycle) frame \(i) must not be Infinite")
            }
        }

        graph.playerNode.stop()
        graph.stop()
        graph.engine.disableManualRenderingMode()
    }

    // MARK: - LiveAudioEngine Control Integration & Transport Tests
    @Test("LiveAudioEngine binds and synchronizes UI controls and transport to AudioGraphController")
    @MainActor
    func testLiveAudioEngineControlBindingAndSync() throws {
        let backend = FakeAudioPlayerBackend()
        let graph = AudioGraphController(force4ChannelOutput: true)
        let liveEngine = LiveAudioEngine(
            graphController: graph,
            permissionProvider: FakeMicrophonePermissionProvider(status: .authorized),
            playerBackend: backend
        )

        // 1. Проверяем привязку Backing controls
        liveEngine.trackFOHVolume = 0.65
        liveEngine.trackIEMVolume = 0.55
        #expect(liveEngine.graphController.backingFOHVolume == 0.65)
        #expect(liveEngine.graphController.backingIEMVolume == 0.55)

        liveEngine.trackIsMuted = true
        #expect(liveEngine.graphController.backingIsMuted == true)
        #expect(liveEngine.graphController.backingFOHGain.outputVolume == 0.0)

        liveEngine.trackIsMuted = false
        #expect(liveEngine.graphController.backingFOHGain.outputVolume == 0.65)

        // 2. Проверяем привязку Mic 1 controls
        liveEngine.mic1.fohVolume = 0.77
        liveEngine.mic1.iemVolume = 0.88
        liveEngine.mic1.reverbSend = 0.44
        #expect(liveEngine.graphController.mic1FOHVolume == 0.77)
        #expect(liveEngine.graphController.mic1IEMVolume == 0.88)
        #expect(liveEngine.graphController.mic1ReverbSendVolume == 0.44)

        liveEngine.mic1.isMuted = true
        #expect(liveEngine.graphController.mic1IsMuted == true)
        #expect(liveEngine.graphController.mic1FOHGain.outputVolume == 0.0)
        #expect(liveEngine.graphController.mic1ReverbSend.outputVolume == 0.0)

        liveEngine.mic1.isMuted = false
        #expect(liveEngine.graphController.mic1FOHGain.outputVolume == 0.77)
        #expect(liveEngine.graphController.mic1ReverbSend.outputVolume == 0.44)

        // 3. Проверяем привязку EQ и компрессора
        liveEngine.mic1.lowCutEnabled = false
        #expect(liveEngine.graphController.mic1LowCutEnabled == false)
        #expect(liveEngine.graphController.mic1EQNode.bands[0].bypass == true)

        liveEngine.mic1.midGain = 3.5
        #expect(liveEngine.graphController.mic1MidGain == 3.5)
        #expect(liveEngine.graphController.mic1EQNode.bands[1].gain == 3.5)

        liveEngine.mic1.compressorEnabled = false
        #expect(liveEngine.graphController.mic1CompressorEnabled == false)
        #expect(liveEngine.graphController.mic1CompressorNode.bypass == true)

        // 4. Проверяем мастер фейдеры
        liveEngine.masterFOHVolume = 0.90
        liveEngine.masterIEMVolume = 0.85
        #expect(liveEngine.graphController.fohMixer.outputVolume == 0.90)
        #expect(liveEngine.graphController.iemMixer.outputVolume == 0.85)

        // 5. Проверяем транспортные функции
        #expect(!liveEngine.isPlaying)
        liveEngine.play()
        #expect(liveEngine.isPlaying)
        liveEngine.pause()
        #expect(!liveEngine.isPlaying)
        liveEngine.togglePlayPause()
        #expect(liveEngine.isPlaying)
        liveEngine.togglePlayPause()
        #expect(!liveEngine.isPlaying)
        liveEngine.seek(to: 5.0)
        #expect(liveEngine.currentTrackTime >= 0.0)
        liveEngine.stop()
        #expect(!liveEngine.isPlaying)
        #expect(liveEngine.currentTrackTime == 0.0)

        liveEngine.graphController.stop()
    }
}
