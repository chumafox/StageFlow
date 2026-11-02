import Foundation
import AVFoundation
import AudioToolbox
import Accelerate

@MainActor
public class MicChannelStrip: ObservableObject, Identifiable {
    public let id = UUID()
    public let name: String
    public let channelIndex: Int
    
    // CoreAudio AU Effects (Single source of truth from AudioGraphController)
    public let eqNode: AVAudioUnitEQ
    public let compressorNode: AVAudioUnitEffect
    
    public var onUpdate: (() -> Void)?
    
    // Level controls
    @Published public var fohVolume: Float = 0.80 {
        didSet { onUpdate?() }
    }
    @Published public var iemVolume: Float = 0.95 {
        didSet { onUpdate?() }
    }
    @Published public var reverbSend: Float = 0.20 {
        didSet { onUpdate?() }
    }
    @Published public var isMuted: Bool = false {
        didSet { onUpdate?() }
    }
    @Published public var isSolo: Bool = false {
        didSet { onUpdate?() }
    }
    
    // Metering (E06: Достоверные измерения)
    @Published public var peakLevel: Float = 0.0
    @Published public var isClipping: Bool = false
    
    // EQ adjustments
    @Published public var lowCutEnabled: Bool = true {
        didSet {
            if eqNode.bands.count > 0 {
                eqNode.bands[0].bypass = !lowCutEnabled
            }
            onUpdate?()
        }
    }
    @Published public var midGain: Float = 1.5 {
        didSet {
            if eqNode.bands.count > 1 {
                eqNode.bands[1].gain = midGain
            }
            onUpdate?()
        }
    }
    @Published public var highGain: Float = 2.0 {
        didSet {
            if eqNode.bands.count > 2 {
                eqNode.bands[2].gain = highGain
            }
            onUpdate?()
        }
    }
    @Published public var compressorEnabled: Bool = true {
        didSet {
            compressorNode.bypass = !compressorEnabled
            onUpdate?()
        }
    }
    
    public init(name: String, channelIndex: Int, eqNode: AVAudioUnitEQ? = nil, compressorNode: AVAudioUnitEffect? = nil) {
        self.name = name
        self.channelIndex = channelIndex
        self.eqNode = eqNode ?? AVAudioUnitEQ(numberOfBands: 3)
        if let comp = compressorNode {
            self.compressorNode = comp
        } else {
            let desc = AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_DynamicsProcessor,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            self.compressorNode = AVAudioUnitEffect(audioComponentDescription: desc)
        }
        
        configureEffects()
    }
    
    private func configureEffects() {
        if eqNode.bands.count >= 3 {
            // Band 0: High-Pass / Low-Cut Filter (80 Hz)
            eqNode.bands[0].filterType = .highPass
            eqNode.bands[0].frequency = 80.0
            eqNode.bands[0].bypass = !lowCutEnabled
            
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
}

@MainActor
public class LiveAudioEngine: ObservableObject, TransportControllerProtocol {
    public let graphController: AudioGraphController
    public let meteringCoordinator: MeteringCoordinator
    public let transportController: TransportController
    
    // Convenience access to underlying graph engine & nodes
    public var engine: AVAudioEngine { graphController.engine }
    public var playerNode: AVAudioPlayerNode { graphController.playerNode }
    public var fohMixer: AVAudioMixerNode { graphController.fohMixer }
    public var iemMixer: AVAudioMixerNode { graphController.iemMixer }
    public var reverbNode: AVAudioUnitReverb { graphController.reverbNode }
    
    // Channels
    @Published public var mic1: MicChannelStrip
    @Published public var mic2: MicChannelStrip
    
    // Backing Track Player
    @Published public var trackFOHVolume: Float = 0.85 { didSet { syncControlsToGraph() } }
    @Published public var trackIEMVolume: Float = 0.70 { didSet { syncControlsToGraph() } }
    @Published public var trackIsMuted: Bool = false { didSet { syncControlsToGraph() } }
    @Published public var trackIsSolo: Bool = false { didSet { syncControlsToGraph() } }
    
    // Transport (E07 / ADR-003: TransportController is single source of truth)
    public var state: TransportState { transportController.state }
    public var isPlaying: Bool { transportController.isPlaying }
    @Published public var transportState: TransportState = .stopped
    @Published public var currentTrackTime: TimeInterval = 0.0
    @Published public var trackDuration: TimeInterval = 0.0
    
    // Master Buses
    @Published public var masterFOHVolume: Float = 1.0 {
        didSet { graphController.masterFOHVolume = masterFOHVolume }
    }
    @Published public var masterIEMVolume: Float = 1.0 {
        didSet { graphController.masterIEMVolume = masterIEMVolume }
    }
    
    // Lifecycle & Diagnostics (E08.1 / E08.3 / E08.7)
    @Published public var engineLifecycleState: EngineLifecycleState = .stopped
    @Published public var diagnosticsReport: DiagnosticsReport = DiagnosticsReport()
    @Published public var isMicPermissionGranted: Bool = true
    
    public let permissionProvider: any MicrophonePermissionProviding
    private var configObserver: NSObjectProtocol?
    
    // ON AIR строго при работающем engine и активном транспорте (E08.3)
    public var isOnAir: Bool {
        let isEngineActive: Bool
        switch engineLifecycleState {
        case .running:
            isEngineActive = true
        case .degraded:
            isEngineActive = graphController.isRunning
        case .starting, .ready, .stopped, .failed:
            isEngineActive = false
        }
        return isEngineActive && transportController.isPlaying
    }
    
    // Metering Snapshots (E06)
    @Published public var fohPeak: Float = 0.0
    @Published public var iemPeak: Float = 0.0
    @Published public var backingPeak: Float = 0.0
    @Published public var fohClipping: Bool = false
    @Published public var iemClipping: Bool = false
    @Published public var backingClipping: Bool = false
    
    @Published public var backingMeter: MeterReading = .silence
    @Published public var mic1Meter: MeterReading = .silence
    @Published public var mic2Meter: MeterReading = .silence
    @Published public var fohMeter: MeterReading = .silence
    @Published public var iemMeter: MeterReading = .silence
    
    private var displayTimer: Timer?
    private var testBuffer: AVAudioPCMBuffer?
    
    public convenience init() {
        self.init(graphController: AudioGraphController())
    }
    
    public init(
        graphController: AudioGraphController,
        clock: any AudioClockProtocol = SystemAudioClock(),
        permissionProvider: any MicrophonePermissionProviding = SystemMicrophonePermissionProvider(),
        playerBackend: (any AudioPlayerBackend)? = nil
    ) {
        self.graphController = graphController
        self.meteringCoordinator = MeteringCoordinator(clock: clock)
        if let backend = playerBackend {
            self.transportController = TransportController(backend: backend)
        } else {
            self.transportController = TransportController(playerNode: graphController.playerNode)
        }
        self.permissionProvider = permissionProvider
        
        self.mic1 = MicChannelStrip(
            name: "Lead Vocal 🎤",
            channelIndex: 0,
            eqNode: graphController.mic1EQNode,
            compressorNode: graphController.mic1CompressorNode
        )
        self.mic2 = MicChannelStrip(
            name: "Backing Vocal 🎙️",
            channelIndex: 1,
            eqNode: graphController.mic2EQNode,
            compressorNode: graphController.mic2CompressorNode
        )
        
        // Проверка микрофонных разрешений (E08.6)
        let permStatus = permissionProvider.checkPermission()
        switch permStatus {
        case .authorized:
            self.isMicPermissionGranted = true
        case .denied:
            self.isMicPermissionGranted = false
            self.graphController.mic1InputNode.outputVolume = 0.0
            self.graphController.mic2InputNode.outputVolume = 0.0
        case .notDetermined:
            self.isMicPermissionGranted = false
        }
        
        setupBindings()
        setupTaps()
        startEngine()
        
        prepareProceduralDemoAudio(format: graphController.stereoFormat)
        startPlaybackTimer()
        
        // Наблюдатель за изменениями конфигурации CoreAudio (E08.5)
        self.configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: graphController.engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleConfigurationChange()
            }
        }
    }
    
    private func setupBindings() {
        mic1.onUpdate = { [weak self] in self?.syncControlsToGraph() }
        mic2.onUpdate = { [weak self] in self?.syncControlsToGraph() }
        syncControlsToGraph()
    }
    
    public func syncControlsToGraph() {
        graphController.backingFOHVolume = trackFOHVolume
        graphController.backingIEMVolume = trackIEMVolume
        graphController.backingIsMuted = trackIsMuted
        graphController.backingIsSolo = trackIsSolo
        
        graphController.mic1FOHVolume = mic1.fohVolume
        graphController.mic1IEMVolume = mic1.iemVolume
        graphController.mic1ReverbSendVolume = mic1.reverbSend
        graphController.mic1IsMuted = mic1.isMuted
        graphController.mic1IsSolo = mic1.isSolo
        graphController.mic1LowCutEnabled = mic1.lowCutEnabled
        graphController.mic1MidGain = mic1.midGain
        graphController.mic1HighGain = mic1.highGain
        graphController.mic1CompressorEnabled = mic1.compressorEnabled
        
        graphController.mic2FOHVolume = mic2.fohVolume
        graphController.mic2IEMVolume = mic2.iemVolume
        graphController.mic2ReverbSendVolume = mic2.reverbSend
        graphController.mic2IsMuted = mic2.isMuted
        graphController.mic2IsSolo = mic2.isSolo
        graphController.mic2LowCutEnabled = mic2.lowCutEnabled
        graphController.mic2MidGain = mic2.midGain
        graphController.mic2HighGain = mic2.highGain
        graphController.mic2CompressorEnabled = mic2.compressorEnabled
        
        graphController.updateEffectiveGains()
    }
    
    private func setupTaps() {
        meteringCoordinator.installTaps(on: graphController)
    }
    
    public func syncMetersFromCoordinator() {
        meteringCoordinator.pollSnapshots()
        
        self.backingMeter = meteringCoordinator.backingMeter
        self.mic1Meter = meteringCoordinator.mic1Meter
        self.mic2Meter = meteringCoordinator.mic2Meter
        self.fohMeter = meteringCoordinator.fohMeter
        self.iemMeter = meteringCoordinator.iemMeter
        
        self.backingPeak = backingMeter.level
        self.backingClipping = backingMeter.isClipping
        
        self.mic1.peakLevel = mic1Meter.level
        self.mic1.isClipping = mic1Meter.isClipping
        
        self.mic2.peakLevel = mic2Meter.level
        self.mic2.isClipping = mic2Meter.isClipping
        
        self.fohPeak = fohMeter.level
        self.fohClipping = fohMeter.isClipping
        
        self.iemPeak = iemMeter.level
        self.iemClipping = iemMeter.isClipping
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
        self.transportController.loadDemoBuffer(buffer: buffer, duration: 20.0)
        syncTransportProperties()
    }
    
    public func loadAudioFile(url: URL) {
        transportController.loadAudioFile(url: url)
        syncTransportProperties()
    }
    
    // MARK: - Lifecycle Management (E08.3 / E08.4 / E08.5)
    
    public func startEngine() {
        self.engineLifecycleState = .starting
        do {
            try graphController.start()
            if !isMicPermissionGranted {
                self.engineLifecycleState = .degraded("Microphone permission denied")
            } else if !graphController.isIEMAvailable {
                self.engineLifecycleState = .degraded("Stereo fallback: IEM unavailable")
            } else {
                self.engineLifecycleState = .running
            }
        } catch {
            let sfErr = (error as? StageFlowError) ?? .engineStartFailure(error.localizedDescription)
            self.engineLifecycleState = .failed(sfErr)
            self.diagnosticsReport.recentErrors.append("Engine start failed: \(sfErr.localizedDescription)")
        }
        updateDiagnosticsReport()
    }
    
    public func stopEngine() {
        graphController.stop()
        self.engineLifecycleState = .stopped
        updateDiagnosticsReport()
    }
    
    public func handleConfigurationChange(force: Bool = false, force4Channel: Bool? = nil) {
        diagnosticsReport.lastRouteEvent = "Configuration change detected at \(Date())"
        
        let newChannels = Int(graphController.engine.outputNode.outputFormat(forBus: 0).channelCount)
        
        // Проверяем, действительно ли изменился формат или маршрут устройства (E08.5)
        let routeChanged = force || (newChannels != graphController.outputChannelCount)
        
        guard routeChanged else {
            updateDiagnosticsReport()
            return
        }
        
        let wasPlaying = transportController.isPlaying
        if wasPlaying {
            transportController.pause()
        }
        
        do {
            try graphController.reconfigure(force4Channel: force4Channel)
            meteringCoordinator.installTaps(on: graphController)
            
            if !isMicPermissionGranted {
                self.engineLifecycleState = .degraded("Microphone permission denied")
            } else if !graphController.isIEMAvailable {
                self.engineLifecycleState = .degraded("Stereo fallback: IEM unavailable")
            } else {
                self.engineLifecycleState = graphController.isRunning ? .running : .ready
            }
        } catch {
            let sfErr = (error as? StageFlowError) ?? .unavailableRoute(error.localizedDescription)
            self.engineLifecycleState = .failed(sfErr)
            self.diagnosticsReport.recentErrors.append("Reconfiguration failed: \(error.localizedDescription)")
        }
        
        updateDiagnosticsReport()
    }
    
    public func requestMicrophonePermission() async {
        let granted = await permissionProvider.requestPermission()
        self.isMicPermissionGranted = granted
        if granted {
            self.diagnosticsReport.micPermission = "Authorized"
            graphController.mic1InputNode.outputVolume = 1.0
            graphController.mic2InputNode.outputVolume = 1.0
            if case .degraded(let reason) = engineLifecycleState, reason.contains("Microphone") {
                self.engineLifecycleState = graphController.isIEMAvailable ? .running : .degraded("Stereo fallback: IEM unavailable")
            }
        } else {
            self.diagnosticsReport.micPermission = "Denied"
            self.engineLifecycleState = .degraded("Microphone permission denied")
            self.graphController.mic1InputNode.outputVolume = 0.0
            self.graphController.mic2InputNode.outputVolume = 0.0
            self.diagnosticsReport.recentErrors.append("Microphone access denied by user.")
        }
        updateDiagnosticsReport()
    }
    
    public func updateDiagnosticsReport() {
        let route = graphController.isIEMAvailable ? "Quadraphonic (FOH 1-2, IEM 3-4)" : "Stereo Fallback (FOH only)"
        let permStr = isMicPermissionGranted ? "Authorized" : "Denied / Unavailable"
        let rate = graphController.stereoFormat.sampleRate
        let channels = graphController.outputChannelCount
        
        self.diagnosticsReport.engineState = engineLifecycleState.displayName
        self.diagnosticsReport.outputRoute = route
        self.diagnosticsReport.outputChannels = channels
        self.diagnosticsReport.sampleRate = rate
        self.diagnosticsReport.isIEMAvailable = graphController.isIEMAvailable
        self.diagnosticsReport.micPermission = permStr
    }
    
    public func play() {
        // Блокировка недопустимых действий при неработающем/упавшем engine (E08.4)
        switch engineLifecycleState {
        case .failed(let err):
            diagnosticsReport.recentErrors.append("Play blocked: engine is failed (\(err.localizedDescription))")
            return
        case .stopped, .starting:
            diagnosticsReport.recentErrors.append("Play blocked: engine is not running (\(engineLifecycleState.displayName))")
            return
        case .ready, .running, .degraded:
            break
        }
        
        // Блокировка при сбое транспорта или отсутствии источника (E08.4)
        if case .failed(let err) = transportController.state {
            diagnosticsReport.recentErrors.append("Play blocked: transport is in failed state (\(err.localizedDescription))")
            return
        }
        
        transportController.play()
        syncTransportProperties()
    }
    
    public func pause() {
        transportController.pause()
        syncTransportProperties()
    }
    
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    public func stop() {
        transportController.stop()
        syncTransportProperties()
    }
    
    public func seek(to time: TimeInterval) {
        transportController.seek(to: time)
        syncTransportProperties()
    }
    
    private func syncTransportProperties() {
        self.transportState = transportController.state
        self.currentTrackTime = transportController.currentTrackTime
        self.trackDuration = transportController.trackDuration
    }
    
    private func startPlaybackTimer() {
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.transportController.pollAndUpdateDisplay()
                self.syncTransportProperties()
                self.syncMetersFromCoordinator()
            }
        }
    }
    
    isolated deinit {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        displayTimer?.invalidate()
        meteringCoordinator.removeTaps()
    }
}
