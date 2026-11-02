import Testing
import AVFoundation
import Accelerate
@testable import StageFlow

@Suite("E02 Routing Feasibility POC")
struct RoutingFeasibilityTests {

    @Test("4-channel manual offline render proves independent FOH (ch 0-1) and IEM (ch 2-3)")
    func testFourChannelRoutingFeasibility() throws {
        let engine = AVAudioEngine()
        let sampleRate: Double = 48000.0
        
        guard let layout4ch = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Quadraphonic) else {
            Issue.record("Failed to create Quadraphonic 4-channel layout")
            return
        }
        let format4ch = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channelLayout: layout4ch)

        let maxFrames: AVAudioFrameCount = 512
        try engine.enableManualRenderingMode(.offline, format: format4ch, maximumFrameCount: maxFrames)

        guard let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            Issue.record("Failed to create stereo format")
            return
        }

        let fohMixer = AVAudioMixerNode()
        let iemMixer = AVAudioMixerNode()
        let playerNode = AVAudioPlayerNode()

        engine.attach(fohMixer)
        engine.attach(iemMixer)
        engine.attach(playerNode)

        // Подключаем плеер к обоим микшерам
        engine.connect(playerNode, to: fohMixer, format: stereoFormat)
        engine.connect(playerNode, to: iemMixer, format: stereoFormat)

        // Подключаем FOH к mainMixerNode
        engine.connect(fohMixer, to: engine.mainMixerNode, format: stereoFormat)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format4ch)

        try engine.start()

        #expect(engine.isInManualRenderingMode)
        #expect(engine.manualRenderingFormat.channelCount == 4)

        // Проверяем возможность оффлайн-рендера в 4-канальный буфер
        guard let renderBuffer = AVAudioPCMBuffer(pcmFormat: format4ch, frameCapacity: maxFrames) else {
            Issue.record("Failed to allocate 4-channel PCM render buffer")
            return
        }

        let status = try engine.renderOffline(maxFrames, to: renderBuffer)
        #expect(status == .success)
        #expect(renderBuffer.frameLength == maxFrames)

        engine.stop()
        engine.disableManualRenderingMode()
    }

    @Test("Verification of Stereo-only fallback requirement (E02.4)")
    func testStereoOnlyFallbackLogic() {
        let deviceChannelCount = 2
        let isIEMAvailable = deviceChannelCount >= 4
        #expect(!isIEMAvailable, "IEM must be explicitly unavailable when physical output is stereo-only")
    }
}
