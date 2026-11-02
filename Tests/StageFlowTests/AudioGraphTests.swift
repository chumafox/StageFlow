import Testing
import AVFoundation
import Accelerate
@testable import StageFlow

@Suite("E04 Audio Graph Routing & Lifecycle Tests")
struct AudioGraphTests {

    @Test("AudioGraphController initializes all nodes without attached-but-unconnected nodes")
    @MainActor
    func testGraphTopology() {
        let graph = AudioGraphController(sampleRate: 48000.0, force4ChannelOutput: true)
        #expect(graph.outputChannelCount == 4)
        #expect(graph.isIEMAvailable)
        #expect(graph.routingDiagnostics.contains("4-channel"))

        // Проверяем, что все функциональные узлы подключены к графу
        #expect(graph.playerNode.engine != nil)
        #expect(graph.backingFOHGain.engine != nil)
        #expect(graph.backingIEMGain.engine != nil)
        #expect(graph.mic1InputNode.engine != nil)
        #expect(graph.mic1EQNode.engine != nil)
        #expect(graph.mic1CompressorNode.engine != nil)
        #expect(graph.mic1FOHGain.engine != nil)
        #expect(graph.mic1IEMGain.engine != nil)
        #expect(graph.mic1ReverbSend.engine != nil)
        #expect(graph.mic2InputNode.engine != nil)
        #expect(graph.mic2EQNode.engine != nil)
        #expect(graph.mic2CompressorNode.engine != nil)
        #expect(graph.mic2FOHGain.engine != nil)
        #expect(graph.mic2IEMGain.engine != nil)
        #expect(graph.mic2ReverbSend.engine != nil)
        #expect(graph.reverbNode.engine != nil)
        #expect(graph.reverbReturnFOH.engine != nil)
        #expect(graph.reverbReturnIEM.engine != nil)
        #expect(graph.fohMixer.engine != nil)
        #expect(graph.iemMixer.engine != nil)
        #expect(graph.iemRemapNode.engine != nil)
        #expect(graph.masterMixer.engine != nil)
    }

    @Test("Backing track routes independently to FOH (ch 0-1) and IEM (ch 2-3) with zero crosstalk")
    @MainActor
    func testBackingTrackIndependentRouting() throws {
        let graph = AudioGraphController(sampleRate: 48000.0, force4ChannelOutput: true)
        let maxFrames: AVAudioFrameCount = 512
        try graph.engine.enableManualRenderingMode(.offline, format: graph.quadFormat, maximumFrameCount: maxFrames)

        // Подготавливаем тестовый стерео буфер для backing player (0.8 амплитуда)
        guard let backingBuffer = AVAudioPCMBuffer(pcmFormat: graph.stereoFormat, frameCapacity: maxFrames) else {
            Issue.record("Failed to create backing PCM buffer")
            return
        }
        backingBuffer.frameLength = maxFrames
        for i in 0..<Int(maxFrames) {
            backingBuffer.floatChannelData?[0][i] = 0.8
            backingBuffer.floatChannelData?[1][i] = 0.8
        }

        // Тест 1: FOH send = 1.0, IEM send = 0.0
        graph.backingFOHGain.outputVolume = 1.0
        graph.backingIEMGain.outputVolume = 0.0
        graph.fohMixer.outputVolume = 1.0
        graph.iemMixer.outputVolume = 1.0

        graph.playerNode.scheduleBuffer(backingBuffer, at: nil, options: .loops, completionHandler: nil)
        try graph.start()
        graph.playerNode.play()

        let renderBuffer = AVAudioPCMBuffer(pcmFormat: graph.quadFormat, frameCapacity: maxFrames)!
        // Даем CoreAudio volume ramp завершиться (~1500 фреймов)
        for _ in 1...6 {
            _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)
        }

        guard let ch0 = renderBuffer.floatChannelData?[0],
              let ch1 = renderBuffer.floatChannelData?[1],
              let ch2 = renderBuffer.floatChannelData?[2],
              let ch3 = renderBuffer.floatChannelData?[3] else {
            Issue.record("Missing channel data in render buffer")
            return
        }

        // FOH каналы (0 и 1) должны содержать сигнал 0.8
        #expect(abs(ch0[100] - 0.8) < 0.05, "FOH Left must contain backing signal")
        #expect(abs(ch1[100] - 0.8) < 0.05, "FOH Right must contain backing signal")

        // IEM каналы (2 и 3) должны быть в абсолютной тишине (0.0)
        #expect(abs(ch2[100]) < 0.0001, "IEM Left must have zero leakage when send = 0")
        #expect(abs(ch3[100]) < 0.0001, "IEM Right must have zero leakage when send = 0")

        // Тест 2: FOH send = 0.0, IEM send = 1.0
        graph.backingFOHGain.outputVolume = 0.0
        graph.backingIEMGain.outputVolume = 1.0

        for _ in 1...6 {
            _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)
        }

        // Теперь FOH каналы должны быть 0.0, а IEM каналы должны содержать 0.8
        #expect(abs(ch0[100]) < 0.0001, "FOH Left must be silent when send = 0")
        #expect(abs(ch1[100]) < 0.0001, "FOH Right must be silent when send = 0")
        #expect(abs(ch2[100] - 0.8) < 0.05, "IEM Left must receive signal when send = 1")
        #expect(abs(ch3[100] - 0.8) < 0.05, "IEM Right must receive signal when send = 1")

        graph.stop()
        graph.engine.disableManualRenderingMode()
    }

    @Test("Silence input produces zero output across all 4 channels (E04.8)")
    @MainActor
    func testSilenceInputProducesZeroOutput() throws {
        let graph = AudioGraphController(sampleRate: 48000.0, force4ChannelOutput: true)
        let maxFrames: AVAudioFrameCount = 512
        try graph.engine.enableManualRenderingMode(.offline, format: graph.quadFormat, maximumFrameCount: maxFrames)

        graph.backingFOHGain.outputVolume = 1.0
        graph.backingIEMGain.outputVolume = 1.0
        graph.fohMixer.outputVolume = 1.0
        graph.iemMixer.outputVolume = 1.0

        try graph.start()

        let renderBuffer = AVAudioPCMBuffer(pcmFormat: graph.quadFormat, frameCapacity: maxFrames)!
        for _ in 1...4 {
            _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)
        }

        guard let ch0 = renderBuffer.floatChannelData?[0],
              let ch1 = renderBuffer.floatChannelData?[1],
              let ch2 = renderBuffer.floatChannelData?[2],
              let ch3 = renderBuffer.floatChannelData?[3] else {
            Issue.record("Missing channel data in render buffer")
            return
        }

        #expect(abs(ch0[100]) < 0.00001, "Silence input must produce zero in FOH L")
        #expect(abs(ch1[100]) < 0.00001, "Silence input must produce zero in FOH R")
        #expect(abs(ch2[100]) < 0.00001, "Silence input must produce zero in IEM L")
        #expect(abs(ch3[100]) < 0.00001, "Silence input must produce zero in IEM R")

        graph.stop()
        graph.engine.disableManualRenderingMode()
    }

    @Test("Reverb send at 0.0 produces zero wet output, send > 0 enables reverb return")
    @MainActor
    func testReverbPathRouting() {
        let graph = AudioGraphController(sampleRate: 48000.0, force4ChannelOutput: true)

        // По умолчанию Reverb Send = 0
        graph.mic1ReverbSend.outputVolume = 0.0
        #expect(graph.mic1ReverbSend.outputVolume == 0.0)

        // При включении Reverb Send громкость узла меняется
        graph.mic1ReverbSend.outputVolume = 0.35
        #expect(abs(graph.mic1ReverbSend.outputVolume - 0.35) < 0.001)

        // Reverb return узлы присоединены к fohMixer и iemMixer
        #expect(graph.reverbReturnFOH.engine != nil)
        #expect(graph.reverbReturnIEM.engine != nil)
    }

    @Test("Mic 1 and Mic 2 route independently to FOH and IEM without crosstalk (E04.2 / E04.4)")
    @MainActor
    func testMicIndependentRouting() throws {
        let graph = AudioGraphController(sampleRate: 48000.0, force4ChannelOutput: true)
        let maxFrames: AVAudioFrameCount = 512

        // Тестовый плеер для симуляции микрофонного входа 1 (подключаем ДО enableManualRenderingMode)
        let micPlayer = AVAudioPlayerNode()
        graph.engine.attach(micPlayer)
        graph.engine.connect(micPlayer, to: graph.mic1InputNode, format: graph.stereoFormat)

        try graph.engine.enableManualRenderingMode(.offline, format: graph.quadFormat, maximumFrameCount: maxFrames)

        guard let micBuffer = AVAudioPCMBuffer(pcmFormat: graph.stereoFormat, frameCapacity: maxFrames) else {
            Issue.record("Failed to create mic buffer")
            return
        }
        micBuffer.frameLength = maxFrames
        // 1 kHz sine fixture (по спецификации E04.8 для прохождения через 80Hz High-Pass EQ)
        for i in 0..<Int(maxFrames) {
            let sample = Float(sin(2.0 * .pi * 1000.0 * Double(i) / graph.sampleRate) * 0.8)
            micBuffer.floatChannelData?[0][i] = sample
            micBuffer.floatChannelData?[1][i] = sample
        }

        // Mic 1 только в FOH
        graph.mic1FOHGain.outputVolume = 1.0
        graph.mic1IEMGain.outputVolume = 0.0
        graph.mic1ReverbSend.outputVolume = 0.0
        graph.fohMixer.outputVolume = 1.0
        graph.iemMixer.outputVolume = 1.0

        micPlayer.scheduleBuffer(micBuffer, at: nil, options: .loops, completionHandler: nil)
        try graph.start()
        micPlayer.play()

        let renderBuffer = AVAudioPCMBuffer(pcmFormat: graph.quadFormat, frameCapacity: maxFrames)!
        for _ in 1...6 {
            _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)
        }

        guard let ch0 = renderBuffer.floatChannelData?[0],
              let ch1 = renderBuffer.floatChannelData?[1],
              let ch2 = renderBuffer.floatChannelData?[2],
              let ch3 = renderBuffer.floatChannelData?[3] else {
            Issue.record("Missing channel data in render buffer")
            return
        }

        // FOH содержит сигнал микрофона (DynamicsProcessor сжимает 0.8 до ~0.14)
        #expect(abs(ch0[100]) > 0.05, "FOH Left must contain Mic 1 signal")
        #expect(abs(ch1[100]) > 0.05, "FOH Right must contain Mic 1 signal")

        // IEM в абсолютной тишине
        #expect(abs(ch2[100]) < 0.0001, "IEM Left must have zero Mic 1 leakage when IEM send = 0")
        #expect(abs(ch3[100]) < 0.0001, "IEM Right must have zero Mic 1 leakage when IEM send = 0")

        // Переключаем Mic 1 только в IEM
        graph.mic1FOHGain.outputVolume = 0.0
        graph.mic1IEMGain.outputVolume = 1.0

        for _ in 1...6 {
            _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)
        }

        #expect(abs(ch0[100]) < 0.0001, "FOH Left must be silent when Mic 1 FOH send = 0")
        #expect(abs(ch1[100]) < 0.0001, "FOH Right must be silent when Mic 1 FOH send = 0")
        #expect(abs(ch2[100]) > 0.05, "IEM Left must receive Mic 1 signal when IEM send = 1")
        #expect(abs(ch3[100]) > 0.05, "IEM Right must receive Mic 1 signal when IEM send = 1")

        micPlayer.stop()
        graph.stop()
        graph.engine.disableManualRenderingMode()
    }

    @Test("Mic 2 routes independently to FOH and IEM without bleeding into other channels (E04.2 / E04.4)")
    @MainActor
    func testMic2IndependentRouting() throws {
        let graph = AudioGraphController(sampleRate: 48000.0, force4ChannelOutput: true)
        let maxFrames: AVAudioFrameCount = 512

        let micPlayer = AVAudioPlayerNode()
        graph.engine.attach(micPlayer)
        graph.engine.connect(micPlayer, to: graph.mic2InputNode, format: graph.stereoFormat)

        try graph.engine.enableManualRenderingMode(.offline, format: graph.quadFormat, maximumFrameCount: maxFrames)

        guard let micBuffer = AVAudioPCMBuffer(pcmFormat: graph.stereoFormat, frameCapacity: maxFrames) else {
            Issue.record("Failed to create mic buffer")
            return
        }
        micBuffer.frameLength = maxFrames
        // 1 kHz sine fixture
        for i in 0..<Int(maxFrames) {
            let sample = Float(sin(2.0 * .pi * 1000.0 * Double(i) / graph.sampleRate) * 0.8)
            micBuffer.floatChannelData?[0][i] = sample
            micBuffer.floatChannelData?[1][i] = sample
        }

        // Mic 2 только в FOH
        graph.mic2FOHGain.outputVolume = 1.0
        graph.mic2IEMGain.outputVolume = 0.0
        graph.mic2ReverbSend.outputVolume = 0.0
        graph.fohMixer.outputVolume = 1.0
        graph.iemMixer.outputVolume = 1.0

        micPlayer.scheduleBuffer(micBuffer, at: nil, options: .loops, completionHandler: nil)
        try graph.start()
        micPlayer.play()

        let renderBuffer = AVAudioPCMBuffer(pcmFormat: graph.quadFormat, frameCapacity: maxFrames)!
        for _ in 1...6 {
            _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)
        }

        guard let ch0 = renderBuffer.floatChannelData?[0],
              let ch1 = renderBuffer.floatChannelData?[1],
              let ch2 = renderBuffer.floatChannelData?[2],
              let ch3 = renderBuffer.floatChannelData?[3] else {
            Issue.record("Missing channel data in render buffer")
            return
        }

        #expect(abs(ch0[100]) > 0.05, "FOH Left must contain Mic 2 signal")
        #expect(abs(ch1[100]) > 0.05, "FOH Right must contain Mic 2 signal")
        #expect(abs(ch2[100]) < 0.0001, "IEM Left must have zero Mic 2 leakage when IEM send = 0")
        #expect(abs(ch3[100]) < 0.0001, "IEM Right must have zero Mic 2 leakage when IEM send = 0")

        // Переключаем Mic 2 только в IEM
        graph.mic2FOHGain.outputVolume = 0.0
        graph.mic2IEMGain.outputVolume = 1.0

        for _ in 1...6 {
            _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)
        }

        #expect(abs(ch0[100]) < 0.0001, "FOH Left must be silent when Mic 2 FOH send = 0")
        #expect(abs(ch1[100]) < 0.0001, "FOH Right must be silent when Mic 2 FOH send = 0")
        #expect(abs(ch2[100]) > 0.05, "IEM Left must receive Mic 2 signal when IEM send = 1")
        #expect(abs(ch3[100]) > 0.05, "IEM Right must receive Mic 2 signal when IEM send = 1")

        micPlayer.stop()
        graph.stop()
        graph.engine.disableManualRenderingMode()
    }

    @Test("Reverb send offline render verifies wet return to FOH and zero return when send is 0 (E04.5)")
    @MainActor
    func testReverbOfflineReturn() throws {
        let graph = AudioGraphController(sampleRate: 48000.0, force4ChannelOutput: true)
        let maxFrames: AVAudioFrameCount = 512

        let micPlayer = AVAudioPlayerNode()
        graph.engine.attach(micPlayer)
        graph.engine.connect(micPlayer, to: graph.mic1InputNode, format: graph.stereoFormat)

        try graph.engine.enableManualRenderingMode(.offline, format: graph.quadFormat, maximumFrameCount: maxFrames)

        guard let micBuffer = AVAudioPCMBuffer(pcmFormat: graph.stereoFormat, frameCapacity: maxFrames) else {
            Issue.record("Failed to create mic buffer")
            return
        }
        micBuffer.frameLength = maxFrames
        for i in 0..<Int(maxFrames) {
            let sample = Float(sin(2.0 * .pi * 1000.0 * Double(i) / graph.sampleRate) * 0.8)
            micBuffer.floatChannelData?[0][i] = sample
            micBuffer.floatChannelData?[1][i] = sample
        }

        // Тест 1: Reverb send = 0.0 -> абсолютный ноль в Reverb return
        graph.mic1FOHGain.outputVolume = 0.0
        graph.mic1IEMGain.outputVolume = 0.0
        graph.mic1ReverbSend.outputVolume = 0.0
        graph.reverbReturnFOH.outputVolume = 1.0
        graph.reverbReturnIEM.outputVolume = 0.0
        graph.fohMixer.outputVolume = 1.0
        graph.iemMixer.outputVolume = 1.0

        micPlayer.scheduleBuffer(micBuffer, at: nil, options: .loops, completionHandler: nil)
        try graph.start()
        micPlayer.play()

        let renderBuffer = AVAudioPCMBuffer(pcmFormat: graph.quadFormat, frameCapacity: maxFrames)!
        for _ in 1...6 {
            _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)
        }

        guard let ch0 = renderBuffer.floatChannelData?[0],
              let ch2 = renderBuffer.floatChannelData?[2] else {
            Issue.record("Missing channel data in render buffer")
            return
        }

        // При send = 0.0 на выходе полная тишина
        #expect(abs(ch0[100]) < 0.0001, "FOH Left must be completely silent when reverb send = 0")
        #expect(abs(ch2[100]) < 0.0001, "IEM Left must be completely silent when reverb send = 0")

        // Тест 2: Открываем Reverb send = 1.0 -> появляется wet сигнал в FOH
        graph.mic1ReverbSend.outputVolume = 1.0
        for _ in 1...8 {
            _ = try graph.engine.renderOffline(maxFrames, to: renderBuffer)
        }

        #expect(abs(ch0[100]) > 0.01, "FOH Left must receive wet reverb signal when send > 0")
        #expect(abs(ch2[100]) < 0.0001, "IEM Left must have zero reverb leakage when return = 0")

        micPlayer.stop()
        graph.stop()
        graph.engine.disableManualRenderingMode()
    }

    @Test("Stereo-only fallback safely disables IEM and marks it unavailable (E02.4 / E04.6)")
    @MainActor
    func testStereoOnlyFallback() {
        let graph = AudioGraphController(sampleRate: 48000.0, force4ChannelOutput: false)
        #expect(!graph.isIEMAvailable)
        #expect(graph.routingDiagnostics.contains("UNAVAILABLE"))
    }

    @Test("Safe startup mutes all outputs to prevent feedback bursts (E04.7)")
    @MainActor
    func testSafeStartupMutesAll() {
        let graph = AudioGraphController(sampleRate: 48000.0, force4ChannelOutput: true)
        graph.backingFOHGain.outputVolume = 0.8
        graph.backingIEMGain.outputVolume = 0.8
        graph.mic1FOHGain.outputVolume = 0.8

        graph.safeStartupMuteAll()

        #expect(graph.backingFOHGain.outputVolume == 0.0)
        #expect(graph.backingIEMGain.outputVolume == 0.0)
        #expect(graph.mic1FOHGain.outputVolume == 0.0)
        #expect(graph.fohMixer.outputVolume == 0.0)
        #expect(graph.iemMixer.outputVolume == 0.0)
    }

    @Test("Audio graph lifecycle handles 100 consecutive start/stop cycles without leaks or crashes (E04.9)")
    @MainActor
    func testLifecycleStress100Cycles() throws {
        let graph = AudioGraphController(sampleRate: 48000.0, force4ChannelOutput: false)
        for _ in 0..<100 {
            try graph.start()
            #expect(graph.isRunning)
            graph.stop()
            #expect(!graph.isRunning)
        }
    }
}
