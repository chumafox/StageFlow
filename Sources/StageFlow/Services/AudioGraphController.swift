import Foundation
import AVFoundation
import AudioToolbox
import Accelerate

/// AudioUnit для маршрутизации стерео-микса IEM в Surround-каналы (LeftSurround & RightSurround) CoreAudio
public final class IEMSurroundRemapperAU: AUAudioUnit, @unchecked Sendable {
    private var inputBus: AUAudioUnitBus!
    private var outputBus: AUAudioUnitBus!
    private var _inputBusArray: AUAudioUnitBusArray!
    private var _outputBusArray: AUAudioUnitBusArray!

    public override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)
        let sampleRate: Double = 48000.0
        let stereoLayout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Stereo)
            ?? AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Mono)!
        let sf = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channelLayout: stereoLayout)
        let iemFmt = AudioGraphController.createIEMSurroundFormat(sampleRate: sampleRate)
        
        inputBus = try AUAudioUnitBus(format: sf)
        outputBus = try AUAudioUnitBus(format: iemFmt)
        _inputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        _outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
    }

    public override var inputBusses: AUAudioUnitBusArray { _inputBusArray }
    public override var outputBusses: AUAudioUnitBusArray { _outputBusArray }

    public override var internalRenderBlock: AUInternalRenderBlock {
        return { _, timestamp, frameCount, _, outputData, _, pullInputBlock in
            guard let pullInputBlock = pullInputBlock else { return kAudioUnitErr_NoConnection }
            var flags: AudioUnitRenderActionFlags = []
            return pullInputBlock(&flags, timestamp, frameCount, 0, outputData)
        }
    }
}

/// Аудиограф с независимой маршрутизацией FOH и IEM, DSP микрофонов и реверберацией
@MainActor
public final class AudioGraphController: ObservableObject {
    public let engine = AVAudioEngine()
    
    // Аудиоформаты
    public let sampleRate: Double
    public let stereoFormat: AVAudioFormat
    public let quadFormat: AVAudioFormat
    public let fohBusFormat: AVAudioFormat
    public let iemBusFormat: AVAudioFormat
    
    // Backing track
    public let playerNode = AVAudioPlayerNode()
    public let backingFOHGain = AVAudioMixerNode()
    public let backingIEMGain = AVAudioMixerNode()
    
    // Микрофон 1
    public let mic1InputNode = AVAudioMixerNode()
    public let mic1EQNode = AVAudioUnitEQ(numberOfBands: 3)
    public let mic1CompressorNode: AVAudioUnitEffect
    public let mic1FOHGain = AVAudioMixerNode()
    public let mic1IEMGain = AVAudioMixerNode()
    public let mic1ReverbSend = AVAudioMixerNode()
    
    // Микрофон 2
    public let mic2InputNode = AVAudioMixerNode()
    public let mic2EQNode = AVAudioUnitEQ(numberOfBands: 3)
    public let mic2CompressorNode: AVAudioUnitEffect
    public let mic2FOHGain = AVAudioMixerNode()
    public let mic2IEMGain = AVAudioMixerNode()
    public let mic2ReverbSend = AVAudioMixerNode()
    
    // Ревербератор
    public let reverbSendMixer = AVAudioMixerNode()
    public let reverbNode = AVAudioUnitReverb()
    public let reverbReturnFOH = AVAudioMixerNode()
    public let reverbReturnIEM = AVAudioMixerNode()
    
    // Мастер-микшеры и преобразователь каналов
    public let fohMixer = AVAudioMixerNode()
    public let iemMixer = AVAudioMixerNode()
    public let iemRemapNode: AVAudioUnitEffect
    public let masterMixer = AVAudioMixerNode()
    
    // Диагностика и статус маршрутизации
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var isIEMAvailable: Bool = false
    @Published public private(set) var outputChannelCount: Int = 2
    @Published public private(set) var routingDiagnostics: String = "Not initialized"
    
    // MARK: - Backing Track Controls (E05.2, E05.5, E05.6)
    @Published public var backingFOHVolume: Float = 0.85 { didSet { updateEffectiveGains() } }
    @Published public var backingIEMVolume: Float = 0.70 { didSet { updateEffectiveGains() } }
    @Published public var backingIsMuted: Bool = false { didSet { updateEffectiveGains() } }
    @Published public var backingIsSolo: Bool = false { didSet { updateEffectiveGains() } }
    
    // MARK: - Mic 1 Controls (E05.3, E05.5, E05.6, E05.7, E05.8, E05.9)
    @Published public var mic1FOHVolume: Float = 0.80 { didSet { updateEffectiveGains() } }
    @Published public var mic1IEMVolume: Float = 0.95 { didSet { updateEffectiveGains() } }
    @Published public var mic1ReverbSendVolume: Float = 0.20 { didSet { updateEffectiveGains() } }
    @Published public var mic1IsMuted: Bool = false { didSet { updateEffectiveGains() } }
    @Published public var mic1IsSolo: Bool = false { didSet { updateEffectiveGains() } }
    @Published public var mic1LowCutEnabled: Bool = true {
        didSet { mic1EQNode.bands[0].bypass = !mic1LowCutEnabled }
    }
    @Published public var mic1MidGain: Float = 1.5 {
        didSet { mic1EQNode.bands[1].gain = mic1MidGain }
    }
    @Published public var mic1HighGain: Float = 2.0 {
        didSet { mic1EQNode.bands[2].gain = mic1HighGain }
    }
    @Published public var mic1CompressorEnabled: Bool = true {
        didSet { mic1CompressorNode.bypass = !mic1CompressorEnabled }
    }
    
    // MARK: - Mic 2 Controls (E05.4, E05.5, E05.6, E05.7, E05.8, E05.9)
    @Published public var mic2FOHVolume: Float = 0.80 { didSet { updateEffectiveGains() } }
    @Published public var mic2IEMVolume: Float = 0.95 { didSet { updateEffectiveGains() } }
    @Published public var mic2ReverbSendVolume: Float = 0.20 { didSet { updateEffectiveGains() } }
    @Published public var mic2IsMuted: Bool = false { didSet { updateEffectiveGains() } }
    @Published public var mic2IsSolo: Bool = false { didSet { updateEffectiveGains() } }
    @Published public var mic2LowCutEnabled: Bool = true {
        didSet { mic2EQNode.bands[0].bypass = !mic2LowCutEnabled }
    }
    @Published public var mic2MidGain: Float = 1.5 {
        didSet { mic2EQNode.bands[1].gain = mic2MidGain }
    }
    @Published public var mic2HighGain: Float = 2.0 {
        didSet { mic2EQNode.bands[2].gain = mic2HighGain }
    }
    @Published public var mic2CompressorEnabled: Bool = true {
        didSet { mic2CompressorNode.bypass = !mic2CompressorEnabled }
    }
    
    // MARK: - Master & Reverb Returns Controls
    @Published public var masterFOHVolume: Float = 1.0 {
        didSet { fohMixer.outputVolume = masterFOHVolume }
    }
    @Published public var masterIEMVolume: Float = 1.0 {
        didSet { iemMixer.outputVolume = masterIEMVolume }
    }
    @Published public var reverbReturnFOHVolume: Float = 1.0 {
        didSet { reverbReturnFOH.outputVolume = reverbReturnFOHVolume }
    }
    @Published public var reverbReturnIEMVolume: Float = 1.0 {
        didSet { reverbReturnIEM.outputVolume = reverbReturnIEMVolume }
    }
    
    public var force4ChannelOutput: Bool = false
    
    /// Пересчёт эффективных коэффициентов усиления с учётом честного Mute и Solo (Mute > Solo priority)
    public func updateEffectiveGains() {
        let anySolo = backingIsSolo || mic1IsSolo || mic2IsSolo
        
        let backingSilenced = backingIsMuted || (anySolo && !backingIsSolo)
        backingFOHGain.outputVolume = backingSilenced ? 0.0 : backingFOHVolume
        backingIEMGain.outputVolume = backingSilenced ? 0.0 : backingIEMVolume
        
        let mic1Silenced = mic1IsMuted || (anySolo && !mic1IsSolo)
        mic1FOHGain.outputVolume = mic1Silenced ? 0.0 : mic1FOHVolume
        mic1IEMGain.outputVolume = mic1Silenced ? 0.0 : mic1IEMVolume
        mic1ReverbSend.outputVolume = mic1Silenced ? 0.0 : mic1ReverbSendVolume
        
        let mic2Silenced = mic2IsMuted || (anySolo && !mic2IsSolo)
        mic2FOHGain.outputVolume = mic2Silenced ? 0.0 : mic2FOHVolume
        mic2IEMGain.outputVolume = mic2Silenced ? 0.0 : mic2IEMVolume
        mic2ReverbSend.outputVolume = mic2Silenced ? 0.0 : mic2ReverbSendVolume
    }
    
    private static let registerAUOnce: Void = {
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: 0x7366726d, // "sfrm"
            componentManufacturer: 0x73746766, // "stgf"
            componentFlags: 0,
            componentFlagsMask: 0
        )
        AUAudioUnit.registerSubclass(IEMSurroundRemapperAU.self, as: desc, name: "IEMSurroundRemapperAU", version: 1)
    }()
    
    private final class NodeBox: @unchecked Sendable {
        var value: AVAudioUnitEffect?
    }
    
    private static func createRemapNode() -> AVAudioUnitEffect {
        _ = registerAUOnce
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: 0x7366726d,
            componentManufacturer: 0x73746766,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        let sema = DispatchSemaphore(value: 0)
        let box = NodeBox()
        AVAudioUnitEffect.instantiate(with: desc, options: []) { unit, _ in
            box.value = unit as? AVAudioUnitEffect
            sema.signal()
        }
        sema.wait()
        return box.value!
    }
    
    public init(sampleRate: Double = 48000.0, force4ChannelOutput: Bool = false) {
        self.sampleRate = sampleRate
        self.force4ChannelOutput = force4ChannelOutput
        
        let stereoLayout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Stereo)
            ?? AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Mono)!
        self.stereoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channelLayout: stereoLayout)
        
        let quadLayout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_AudioUnit_4)
            ?? AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Quadraphonic)!
        self.quadFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channelLayout: quadLayout)
        
        // FOH формат: стерео Left (1) & Right (2)
        self.fohBusFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channelLayout: stereoLayout)
        
        // IEM формат: стерео LeftSurround (5) & RightSurround (6) для CoreAudio quadraphonic
        self.iemBusFormat = AudioGraphController.createIEMSurroundFormat(sampleRate: sampleRate)
        
        // Создание компрессоров DynamicsProcessor
        let compDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        self.mic1CompressorNode = AVAudioUnitEffect(audioComponentDescription: compDesc)
        self.mic2CompressorNode = AVAudioUnitEffect(audioComponentDescription: compDesc)
        self.iemRemapNode = AudioGraphController.createRemapNode()
        
        configureEQ(mic1EQNode)
        configureEQ(mic2EQNode)
        configureCompressor(mic1CompressorNode)
        configureCompressor(mic2CompressorNode)
        configureReverb()
        
        setupGraph(force4Channel: force4ChannelOutput)
        updateEffectiveGains()
    }
    
    private func configureCompressor(_ comp: AVAudioUnitEffect) {
        let au = comp.audioUnit
        AudioUnitSetParameter(au, AudioUnitParameterID(kDynamicsProcessorParam_Threshold), kAudioUnitScope_Global, 0, -18.0, 0)
        AudioUnitSetParameter(au, AudioUnitParameterID(kDynamicsProcessorParam_HeadRoom), kAudioUnitScope_Global, 0, 5.0, 0)
        AudioUnitSetParameter(au, AudioUnitParameterID(kDynamicsProcessorParam_AttackTime), kAudioUnitScope_Global, 0, 0.005, 0)
        AudioUnitSetParameter(au, AudioUnitParameterID(kDynamicsProcessorParam_ReleaseTime), kAudioUnitScope_Global, 0, 0.100, 0)
    }
    
    public nonisolated static func createIEMSurroundFormat(sampleRate: Double) -> AVAudioFormat {
        let desc = [
            AudioChannelDescription(mChannelLabel: kAudioChannelLabel_LeftSurround, mChannelFlags: [], mCoordinates: (0, 0, 0)),
            AudioChannelDescription(mChannelLabel: kAudioChannelLabel_RightSurround, mChannelFlags: [], mCoordinates: (0, 0, 0))
        ]
        let offset = MemoryLayout.offset(of: \AudioChannelLayout.mChannelDescriptions) ?? 12
        let size = offset + MemoryLayout<AudioChannelDescription>.size * 2
        let raw = malloc(size)!
        let acl = raw.bindMemory(to: AudioChannelLayout.self, capacity: 1)
        acl.pointee.mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions
        acl.pointee.mChannelBitmap = []
        acl.pointee.mNumberChannelDescriptions = 2
        let descs = raw.advanced(by: offset).bindMemory(to: AudioChannelDescription.self, capacity: 2)
        descs[0] = desc[0]
        descs[1] = desc[1]
        let layout = AVAudioChannelLayout(layout: UnsafePointer(acl))
        free(raw)
        return AVAudioFormat(standardFormatWithSampleRate: sampleRate, channelLayout: layout)
    }
    
    private func configureEQ(_ eq: AVAudioUnitEQ) {
        // Band 0: Low-Cut / High-Pass 80 Hz
        eq.bands[0].filterType = .highPass
        eq.bands[0].frequency = 80.0
        eq.bands[0].bypass = false
        
        // Band 1: Vocal Presence 2.8 kHz
        eq.bands[1].filterType = .parametric
        eq.bands[1].frequency = 2800.0
        eq.bands[1].bandwidth = 1.2
        eq.bands[1].gain = 1.5
        eq.bands[1].bypass = false
        
        // Band 2: Air 10 kHz
        eq.bands[2].filterType = .highShelf
        eq.bands[2].frequency = 10000.0
        eq.bands[2].gain = 2.0
        eq.bands[2].bypass = false
    }
    
    private func configureReverb() {
        reverbNode.loadFactoryPreset(.largeHall2)
        reverbNode.wetDryMix = 100.0
    }
    
    public func setupGraph(force4Channel: Bool = false) {
        // Очищаем старые привязки перед сборкой
        engine.stop()
        
        // 1. Прикрепляем все узлы к engine
        let allNodes: [AVAudioNode] = [
            playerNode,
            backingFOHGain, backingIEMGain,
            mic1InputNode, mic1EQNode, mic1CompressorNode, mic1FOHGain, mic1IEMGain, mic1ReverbSend,
            mic2InputNode, mic2EQNode, mic2CompressorNode, mic2FOHGain, mic2IEMGain, mic2ReverbSend,
            reverbSendMixer, reverbNode, reverbReturnFOH, reverbReturnIEM,
            fohMixer, iemMixer, iemRemapNode, masterMixer
        ]
        for node in allNodes {
            engine.attach(node)
        }
        
        // 7. Выходная маршрутизация (FOH & IEM)
        let hwChannels = force4Channel ? 4 : Int(engine.outputNode.outputFormat(forBus: 0).channelCount)
        self.outputChannelCount = hwChannels
        self.isIEMAvailable = hwChannels >= 4
        
        // 2. Коммутация Backing Track: player -> FOH send, IEM send
        if isIEMAvailable {
            engine.connect(playerNode, to: [
                AVAudioConnectionPoint(node: backingFOHGain, bus: 0),
                AVAudioConnectionPoint(node: backingIEMGain, bus: 0)
            ], fromBus: 0, format: stereoFormat)
            engine.connect(backingIEMGain, to: iemMixer, fromBus: 0, toBus: 0, format: stereoFormat)
        } else {
            engine.connect(playerNode, to: backingFOHGain, fromBus: 0, toBus: 0, format: stereoFormat)
        }
        engine.connect(backingFOHGain, to: fohMixer, fromBus: 0, toBus: 0, format: stereoFormat)
        
        // 3. Коммутация Mic 1: Input -> EQ -> Compressor -> Split (FOH, IEM, ReverbSend)
        engine.connect(mic1InputNode, to: mic1EQNode, format: stereoFormat)
        engine.connect(mic1EQNode, to: mic1CompressorNode, format: stereoFormat)
        engine.connect(mic1CompressorNode, to: [
            AVAudioConnectionPoint(node: mic1FOHGain, bus: 0),
            AVAudioConnectionPoint(node: mic1IEMGain, bus: 0),
            AVAudioConnectionPoint(node: mic1ReverbSend, bus: 0)
        ], fromBus: 0, format: stereoFormat)
        engine.connect(mic1FOHGain, to: fohMixer, fromBus: 0, toBus: 1, format: stereoFormat)
        engine.connect(mic1IEMGain, to: iemMixer, fromBus: 0, toBus: 1, format: stereoFormat)
        engine.connect(mic1ReverbSend, to: reverbSendMixer, fromBus: 0, toBus: 0, format: stereoFormat)
        
        // 4. Коммутация Mic 2: Input -> EQ -> Compressor -> Split (FOH, IEM, ReverbSend)
        engine.connect(mic2InputNode, to: mic2EQNode, format: stereoFormat)
        engine.connect(mic2EQNode, to: mic2CompressorNode, format: stereoFormat)
        engine.connect(mic2CompressorNode, to: [
            AVAudioConnectionPoint(node: mic2FOHGain, bus: 0),
            AVAudioConnectionPoint(node: mic2IEMGain, bus: 0),
            AVAudioConnectionPoint(node: mic2ReverbSend, bus: 0)
        ], fromBus: 0, format: stereoFormat)
        engine.connect(mic2FOHGain, to: fohMixer, fromBus: 0, toBus: 2, format: stereoFormat)
        engine.connect(mic2IEMGain, to: iemMixer, fromBus: 0, toBus: 2, format: stereoFormat)
        engine.connect(mic2ReverbSend, to: reverbSendMixer, fromBus: 0, toBus: 1, format: stereoFormat)
        
        // 5. Коммутация Reverb: sends -> reverbSendMixer -> reverbNode -> returnFOH & returnIEM -> fohMixer & iemMixer
        engine.connect(reverbSendMixer, to: reverbNode, format: stereoFormat)
        engine.connect(reverbNode, to: [
            AVAudioConnectionPoint(node: reverbReturnFOH, bus: 0),
            AVAudioConnectionPoint(node: reverbReturnIEM, bus: 0)
        ], fromBus: 0, format: stereoFormat)
        engine.connect(reverbReturnFOH, to: fohMixer, fromBus: 0, toBus: 3, format: stereoFormat)
        engine.connect(reverbReturnIEM, to: iemMixer, fromBus: 0, toBus: 3, format: stereoFormat)
        
        // 6. Базовые уровни внутренних входных микшеров
        mic1InputNode.outputVolume = 1.0
        mic2InputNode.outputVolume = 1.0
        reverbSendMixer.outputVolume = 1.0
        reverbReturnFOH.outputVolume = 1.0
        reverbReturnIEM.outputVolume = 1.0
        fohMixer.outputVolume = 1.0
        iemMixer.outputVolume = 1.0
        masterMixer.outputVolume = 1.0

        // 7. Выходная маршрутизация (FOH & IEM)
        if isIEMAvailable {
            // 4-канальный режим: FOH в ch 0-1 (Front L/R), IEM в ch 2-3 (Surround L/R)
            engine.connect(fohMixer, to: masterMixer, fromBus: 0, toBus: 0, format: stereoFormat)
            engine.connect(iemMixer, to: iemRemapNode, format: stereoFormat)
            engine.connect(iemRemapNode, to: masterMixer, fromBus: 0, toBus: 1, format: iemBusFormat)
            engine.connect(masterMixer, to: engine.outputNode, format: quadFormat)
            self.routingDiagnostics = "4-channel Quadraphonic: FOH -> Ch 1-2, IEM -> Ch 3-4 (Independent)"
        } else {
            // 2-канальный режим (Stereo-only fallback по ADR-001 / E02.4)
            // FOH идет на мастер, IEM НЕ подмешивается в FOH
            engine.connect(fohMixer, to: engine.mainMixerNode, format: stereoFormat)
            self.routingDiagnostics = "2-channel Stereo: FOH -> Ch 1-2 (Active), IEM -> UNAVAILABLE"
        }
    }
    
    public func start() throws {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
            self.isRunning = true
        } catch {
            self.isRunning = false
            throw StageFlowError.engineStartFailure(error.localizedDescription)
        }
    }
    
    public func stop() {
        if engine.isRunning {
            engine.stop()
        }
        self.isRunning = false
    }
    
    /// Безопасная переконфигурация аудиографа при смене аудиоустройства или маршрута (E08.5)
    public func reconfigure(force4Channel: Bool? = nil) throws {
        let wasRunning = engine.isRunning
        if wasRunning {
            engine.stop()
        }
        
        if let f = force4Channel {
            self.force4ChannelOutput = f
        }
        let target4Ch = self.force4ChannelOutput || (Int(engine.outputNode.outputFormat(forBus: 0).channelCount) >= 4)
        let hwChannels = target4Ch ? 4 : Int(engine.outputNode.outputFormat(forBus: 0).channelCount)
        self.outputChannelCount = hwChannels
        self.isIEMAvailable = target4Ch
        
        // Отключаем динамические связи
        engine.disconnectNodeOutput(playerNode)
        engine.disconnectNodeOutput(backingIEMGain)
        engine.disconnectNodeOutput(backingFOHGain)
        engine.disconnectNodeOutput(fohMixer)
        engine.disconnectNodeOutput(iemMixer)
        engine.disconnectNodeOutput(iemRemapNode)
        engine.disconnectNodeOutput(masterMixer)
        
        // 2. Коммутация Backing Track: player -> FOH send, IEM send
        if isIEMAvailable {
            engine.connect(playerNode, to: [
                AVAudioConnectionPoint(node: backingFOHGain, bus: 0),
                AVAudioConnectionPoint(node: backingIEMGain, bus: 0)
            ], fromBus: 0, format: stereoFormat)
            engine.connect(backingIEMGain, to: iemMixer, fromBus: 0, toBus: 0, format: stereoFormat)
        } else {
            engine.connect(playerNode, to: backingFOHGain, fromBus: 0, toBus: 0, format: stereoFormat)
        }
        engine.connect(backingFOHGain, to: fohMixer, fromBus: 0, toBus: 0, format: stereoFormat)
        
        // 7. Выходная маршрутизация (FOH & IEM)
        if isIEMAvailable {
            engine.connect(fohMixer, to: masterMixer, fromBus: 0, toBus: 0, format: stereoFormat)
            engine.connect(iemMixer, to: iemRemapNode, format: stereoFormat)
            engine.connect(iemRemapNode, to: masterMixer, fromBus: 0, toBus: 1, format: iemBusFormat)
            engine.connect(masterMixer, to: engine.outputNode, format: quadFormat)
            self.routingDiagnostics = "4-channel Quadraphonic: FOH -> Ch 1-2, IEM -> Ch 3-4 (Independent)"
        } else {
            engine.connect(fohMixer, to: engine.mainMixerNode, format: stereoFormat)
            self.routingDiagnostics = "2-channel Stereo: FOH -> Ch 1-2 (Active), IEM -> UNAVAILABLE"
        }
        
        updateEffectiveGains()
        
        if wasRunning {
            do {
                try engine.start()
                self.isRunning = true
            } catch {
                self.isRunning = false
                throw StageFlowError.engineStartFailure("Failed to restart engine after reconfiguration: \(error.localizedDescription)")
            }
        }
    }
    
    // Безопасный startup (E04.7)
    public func safeStartupMuteAll() {
        backingFOHGain.outputVolume = 0.0
        backingIEMGain.outputVolume = 0.0
        mic1FOHGain.outputVolume = 0.0
        mic1IEMGain.outputVolume = 0.0
        mic1ReverbSend.outputVolume = 0.0
        mic2FOHGain.outputVolume = 0.0
        mic2IEMGain.outputVolume = 0.0
        mic2ReverbSend.outputVolume = 0.0
        fohMixer.outputVolume = 0.0
        iemMixer.outputVolume = 0.0
    }
}
