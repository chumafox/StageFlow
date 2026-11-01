import Foundation
import AVFoundation
import AudioToolbox
import Accelerate

public class MicChannelStrip: ObservableObject, Identifiable {
    public let id = UUID()
    public let name: String
    public let channelIndex: Int
    
    // CoreAudio AU Effects
    public let eqNode = AVAudioUnitEQ(numberOfBands: 3)
    public let compressorNode: AVAudioUnitEffect
    
    // Level controls
    @Published public var fohVolume: Float = 0.8
    @Published public var iemVolume: Float = 0.95
    @Published public var reverbSend: Float = 0.20
    @Published public var isMuted: Bool = false
    @Published public var isSolo: Bool = false
    @Published public var peakLevel: Float = 0.0
    
    // EQ adjustments
    @Published public var lowCutEnabled: Bool = true {
        didSet { eqNode.bands[0].bypass = !lowCutEnabled }
    }
    @Published public var midGain: Float = 1.5 {
        didSet { eqNode.bands[1].gain = midGain }
    }
    @Published public var highGain: Float = 2.0 {
        didSet { eqNode.bands[2].gain = highGain }
    }
    
    public init(name: String, channelIndex: Int) {
        self.name = name
        self.channelIndex = channelIndex
        
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        self.compressorNode = AVAudioUnitEffect(audioComponentDescription: desc)
        
        configureEffects()
    }
    
    private func configureEffects() {
        // Band 0: High-Pass / Low-Cut Filter (80 Hz)
        eqNode.bands[0].filterType = .highPass
        eqNode.bands[0].frequency = 80.0
        eqNode.bands[0].bypass = false
        
        // Band 1: Vocal Presence Peak (2.8 kHz, Q = 1.2)
        eqNode.bands[1].filterType = .parametric
        eqNode.bands[1].frequency = 2800.0
        eqNode.bands[1].bandwidth = 1.2
        eqNode.bands[1].gain = midGain
        eqNode.bands[1].bypass = false
        
        // Band 2: Air / High Shelf (10 kHz)
        eqNode.bands[2].filterType = .highShelf
        eqNode.bands[2].frequency = 10000.0
        eqNode.bands[2].gain = highGain
        eqNode.bands[2].bypass = false
    }
}

public class LiveAudioEngine: ObservableObject {
    public let engine = AVAudioEngine()
    
    // Channels
    @Published public var mic1 = MicChannelStrip(name: "Lead Vocal 🎤", channelIndex: 0)
    @Published public var mic2 = MicChannelStrip(name: "Backing Vocal 🎙️", channelIndex: 1)
    
    // Backing Track Player
    public let playerNode = AVAudioPlayerNode()
    @Published public var trackFOHVolume: Float = 0.85
    @Published public var trackIEMVolume: Float = 0.70
    @Published public var isPlaying: Bool = false
    @Published public var currentTrackTime: TimeInterval = 0.0
    @Published public var trackDuration: TimeInterval = 0.0
    
    // Master Buses
    public let reverbNode = AVAudioUnitReverb()
    public let fohMixer = AVAudioMixerNode()
    public let iemMixer = AVAudioMixerNode()
    
    @Published public var masterFOHVolume: Float = 1.0 {
        didSet { fohMixer.outputVolume = masterFOHVolume }
    }
    @Published public var masterIEMVolume: Float = 1.0 {
        didSet { iemMixer.outputVolume = masterIEMVolume }
    }
    @Published public var fohPeak: Float = 0.0
    @Published public var iemPeak: Float = 0.0
    
    private var displayTimer: Timer?
    private var testBuffer: AVAudioPCMBuffer?
    
    public init() {
        setupGraph()
    }
    
    private func setupGraph() {
        // 1. Пространственный ревербератор
        reverbNode.loadFactoryPreset(.largeHall2)
        reverbNode.wetDryMix = 100.0
        
        engine.attach(playerNode)
        engine.attach(reverbNode)
        engine.attach(fohMixer)
        engine.attach(iemMixer)
        
        // 2. Подключение микрофонных модулей AU
        for mic in [mic1, mic2] {
            engine.attach(mic.eqNode)
            engine.attach(mic.compressorNode)
        }
        
        let format = engine.outputNode.outputFormat(forBus: 0)
        
        // 3. Коммутация в FOH
        engine.connect(playerNode, to: fohMixer, format: format)
        engine.connect(fohMixer, to: engine.mainMixerNode, format: format)
        
        // 4. Установка Tap для мониторинга уровней
        fohMixer.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self, let channelData = buffer.floatChannelData else { return }
            var rms: Float = 0.0
            vDSP_rmsqv(channelData.pointee, 1, &rms, vDSP_Length(buffer.frameLength))
            DispatchQueue.main.async {
                self.fohPeak = min(max(rms * 2.5, 0.0), 1.0)
                self.iemPeak = min(max(rms * 2.2, 0.0), 1.0)
                if self.isPlaying {
                    self.mic1.peakLevel = min(self.mic1.fohVolume * rms * 1.8, 1.0)
                    self.mic2.peakLevel = min(self.mic2.fohVolume * rms * 1.5, 1.0)
                } else {
                    self.mic1.peakLevel = 0.0
                    self.mic2.peakLevel = 0.0
                }
            }
        }
        
        prepareProceduralDemoAudio(format: format)
        
        do {
            try engine.start()
        } catch {
            print("Failed to start AVAudioEngine: \(error)")
        }
        
        startPlaybackTimer()
    }
    
    private func prepareProceduralDemoAudio(format: AVAudioFormat) {
        let sampleRate = format.sampleRate > 0 ? format.sampleRate : 44100.0
        let frameCount = AVAudioFrameCount(sampleRate * 20)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        
        let channelsCount = Int(format.channelCount)
        for ch in 0..<channelsCount {
            guard let chData = buffer.floatChannelData?[ch] else { continue }
            for i in 0..<Int(frameCount) {
                let time = Double(i) / sampleRate
                let bassFreq = 110.0
                let chordFreq = 220.0 * (1.0 + Double((Int(time * 2) % 4)) * 0.25)
                let sample = sin(2.0 * .pi * bassFreq * time) * 0.10 + sin(2.0 * .pi * chordFreq * time) * 0.08
                chData[i] = Float(sample)
            }
        }
        self.testBuffer = buffer
        self.trackDuration = 20.0
        playerNode.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
    }
    
    public func loadAudioFile(url: URL) {
        guard let file = try? AVAudioFile(forReading: url) else { return }
        let format = file.processingFormat
        let duration = Double(file.length) / format.sampleRate
        
        playerNode.stop()
        self.trackDuration = duration
        self.currentTrackTime = 0.0
        playerNode.scheduleFile(file, at: nil, completionHandler: nil)
    }
    
    public func togglePlayPause() {
        if isPlaying {
            playerNode.pause()
            isPlaying = false
        } else {
            playerNode.play()
            isPlaying = true
        }
    }
    
    public func stop() {
        playerNode.stop()
        isPlaying = false
        currentTrackTime = 0.0
        if let buffer = testBuffer {
            playerNode.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        }
    }
    
    public func seek(to time: TimeInterval) {
        currentTrackTime = max(0, min(time, trackDuration))
    }
    
    private func startPlaybackTimer() {
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }
            if self.trackDuration > 0 {
                self.currentTrackTime += 0.05
                if self.currentTrackTime >= self.trackDuration {
                    self.currentTrackTime = 0.0
                }
            }
        }
    }
}
