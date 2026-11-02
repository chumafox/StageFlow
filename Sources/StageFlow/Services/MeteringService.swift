import Foundation
import AVFoundation
import Accelerate

/// Системные аудиочасы по умолчанию, использующие monotonic ProcessInfo.systemUptime
public struct SystemAudioClock: AudioClockProtocol {
    public init() {}
    public func currentAudioTime() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}

/// Симулированные часы для детерминированного тестирования временных характеристик (Clip Hold, Decay)
public final class SimulatedAudioClock: AudioClockProtocol, @unchecked Sendable {
    public private(set) var currentTime: TimeInterval
    
    public init(initialTime: TimeInterval = 0.0) {
        self.currentTime = initialTime
    }
    
    public func currentAudioTime() -> TimeInterval {
        currentTime
    }
    
    public func advance(by seconds: TimeInterval) {
        currentTime += seconds
    }
    
    public func setTime(_ time: TimeInterval) {
        currentTime = time
    }
}

/// Снимок измерений аудиосигнала (калиброван в dBFS)
public struct MeterReading: Sendable, Equatable {
    /// Пиковый уровень в dBFS (-120.0 ... 0.0 dBFS)
    public let peakDB: Float
    /// Среднеквадратичный уровень (RMS) в dBFS (-120.0 ... 0.0 dBFS)
    public let rmsDB: Float
    /// Линейная пиковая амплитуда (0.0 ... 1.0+)
    public let peakLinear: Float
    /// Линейная RMS амплитуда (0.0 ... 1.0+)
    public let rmsLinear: Float
    /// Нормализованный уровень для отображения на индикаторе (0.0 ... 1.0, калиброван от -60 dBFS до 0 dBFS)
    public let level: Float
    /// Флаг удержания клиппирования (Peak >= -0.1 dBFS, удержание 1.5 сек)
    public let isClipping: Bool
    
    public static let silence = MeterReading(
        peakDB: -120.0,
        rmsDB: -120.0,
        peakLinear: 0.0,
        rmsLinear: 0.0,
        level: 0.0,
        isClipping: false
    )
    
    public init(
        peakDB: Float,
        rmsDB: Float,
        peakLinear: Float,
        rmsLinear: Float,
        level: Float,
        isClipping: Bool
    ) {
        self.peakDB = peakDB
        self.rmsDB = rmsDB
        self.peakLinear = peakLinear
        self.rmsLinear = rmsLinear
        self.level = level
        self.isClipping = isClipping
    }
}

/// Потокобезопасный процессор измерений канала
/// Вычисляет Peak и RMS по всем аудиоканалам через Accelerate vDSP, производит калибровку в dBFS,
/// реализует спад (decay) пиков и удержание индикации перегрузки (Clip Hold).
public final class ChannelMeterProcessor: @unchecked Sendable {
    public let clock: any AudioClockProtocol
    public let decayRateDBPerSecond: Float
    public let clipHoldDuration: TimeInterval
    public let clipThresholdDB: Float
    public let floorDB: Float
    
    private var lock = os_unfair_lock()
    private var accumulatedPeakLinear: Float = 0.0
    private var latestRMSLinear: Float = 0.0
    
    private var currentPeakDB: Float = -120.0
    private var clipExpiryTime: TimeInterval = 0.0
    private var lastUpdateTime: TimeInterval = 0.0
    
    public init(
        clock: any AudioClockProtocol = SystemAudioClock(),
        decayRateDBPerSecond: Float = 20.0,
        clipHoldDuration: TimeInterval = 1.5,
        clipThresholdDB: Float = -0.1,
        floorDB: Float = -60.0
    ) {
        self.clock = clock
        self.decayRateDBPerSecond = decayRateDBPerSecond
        self.clipHoldDuration = clipHoldDuration
        self.clipThresholdDB = clipThresholdDB
        self.floorDB = floorDB
        self.lastUpdateTime = clock.currentAudioTime()
    }
    
    /// Обработка аудио-буфера в realtime audio callback потоке без аллокаций памяти и блокировок ядра
    public func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let frames = vDSP_Length(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        var maxPeak: Float = 0.0
        var sumSquares: Float = 0.0
        
        for ch in 0..<channelCount {
            let data = channelData[ch]
            var chPeak: Float = 0.0
            vDSP_maxmgv(data, 1, &chPeak, frames)
            if chPeak > maxPeak { maxPeak = chPeak }
            
            var chRMS: Float = 0.0
            vDSP_rmsqv(data, 1, &chRMS, frames)
            sumSquares += chRMS * chRMS
        }
        let rms = channelCount > 0 ? sqrt(sumSquares / Float(channelCount)) : 0.0
        
        os_unfair_lock_lock(&lock)
        if maxPeak > accumulatedPeakLinear {
            accumulatedPeakLinear = maxPeak
        }
        latestRMSLinear = rms
        os_unfair_lock_unlock(&lock)
    }
    
    /// Обновление состояния и получение снимка измерений (вызывается из MainActor с частотой ~25 Гц)
    public func updateSnapshot() -> MeterReading {
        let now = clock.currentAudioTime()
        let dt = Float(max(0.0, now - lastUpdateTime))
        lastUpdateTime = now
        
        os_unfair_lock_lock(&lock)
        let rawPeakLinear = accumulatedPeakLinear
        let rawRMSLinear = latestRMSLinear
        accumulatedPeakLinear = 0.0
        os_unfair_lock_unlock(&lock)
        
        // 1. Вычисление dBFS
        let rawPeakDB = rawPeakLinear > 1e-6 ? 20.0 * log10(rawPeakLinear) : -120.0
        let rawRMSDB = rawRMSLinear > 1e-6 ? 20.0 * log10(rawRMSLinear) : -120.0
        
        // 2. Ballistics: Мгновенная атака, баллистический спад (Decay)
        if rawPeakDB >= currentPeakDB {
            currentPeakDB = rawPeakDB
        } else {
            currentPeakDB = max(rawPeakDB, currentPeakDB - decayRateDBPerSecond * dt)
        }
        
        // 3. Clip Hold (удержание перегрузки)
        if rawPeakDB >= clipThresholdDB {
            clipExpiryTime = now + clipHoldDuration
        }
        let isClipping = (now < clipExpiryTime)
        
        // 4. Нормализованная шкала индикатора (floorDB ... 0.0 dBFS -> 0.0 ... 1.0)
        let normalizedLevel: Float
        if currentPeakDB <= floorDB {
            normalizedLevel = 0.0
        } else if currentPeakDB >= 0.0 {
            normalizedLevel = 1.0
        } else {
            normalizedLevel = (currentPeakDB - floorDB) / (0.0 - floorDB)
        }
        
        return MeterReading(
            peakDB: currentPeakDB,
            rmsDB: rawRMSDB,
            peakLinear: rawPeakLinear,
            rmsLinear: rawRMSLinear,
            level: normalizedLevel,
            isClipping: isClipping
        )
    }
    
    /// Сброс накопленных пиков и состояния
    public func reset() {
        os_unfair_lock_lock(&lock)
        accumulatedPeakLinear = 0.0
        latestRMSLinear = 0.0
        currentPeakDB = -120.0
        clipExpiryTime = 0.0
        lastUpdateTime = clock.currentAudioTime()
        os_unfair_lock_unlock(&lock)
    }
}

/// Координатор измерений микшера: устанавливает Taps на целевые узлы AudioGraphController,
/// производит coalescing измерений с частотой 25 Гц и публикует состояния на @MainActor.
@MainActor
public final class MeteringCoordinator: ObservableObject {
    public let backingProcessor: ChannelMeterProcessor
    public let mic1Processor: ChannelMeterProcessor
    public let mic2Processor: ChannelMeterProcessor
    public let fohProcessor: ChannelMeterProcessor
    public let iemProcessor: ChannelMeterProcessor
    
    @Published public private(set) var backingMeter: MeterReading = .silence
    @Published public private(set) var mic1Meter: MeterReading = .silence
    @Published public private(set) var mic2Meter: MeterReading = .silence
    @Published public private(set) var fohMeter: MeterReading = .silence
    @Published public private(set) var iemMeter: MeterReading = .silence
    
    private var snapshotTimer: Timer?
    private weak var activeGraph: AudioGraphController?
    
    public init(clock: any AudioClockProtocol = SystemAudioClock()) {
        self.backingProcessor = ChannelMeterProcessor(clock: clock)
        self.mic1Processor = ChannelMeterProcessor(clock: clock)
        self.mic2Processor = ChannelMeterProcessor(clock: clock)
        self.fohProcessor = ChannelMeterProcessor(clock: clock)
        self.iemProcessor = ChannelMeterProcessor(clock: clock)
        
        startSnapshotTimer()
    }
    
    /// Установка аудиотапов на узлы графа в точках ADR-004
    public func installTaps(on graph: AudioGraphController) {
        removeTaps()
        self.activeGraph = graph
        let format = graph.stereoFormat
        let bufferSize: AVAudioFrameCount = 1024
        
        // 1. Backing Post-Fader Tap
        graph.backingFOHGain.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            self?.backingProcessor.processBuffer(buffer)
        }
        
        // 2. Mic 1 Post-Fader Tap
        graph.mic1FOHGain.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            self?.mic1Processor.processBuffer(buffer)
        }
        
        // 3. Mic 2 Post-Fader Tap
        graph.mic2FOHGain.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            self?.mic2Processor.processBuffer(buffer)
        }
        
        // 4. FOH Post-Master Tap
        graph.fohMixer.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            self?.fohProcessor.processBuffer(buffer)
        }
        
        // 5. IEM Post-Master Tap (полностью независим от FOH)
        graph.iemMixer.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            self?.iemProcessor.processBuffer(buffer)
        }
    }
    
    /// Безопасное снятие установленных тапов
    public func removeTaps() {
        guard let graph = activeGraph else { return }
        graph.backingFOHGain.removeTap(onBus: 0)
        graph.mic1FOHGain.removeTap(onBus: 0)
        graph.mic2FOHGain.removeTap(onBus: 0)
        graph.fohMixer.removeTap(onBus: 0)
        graph.iemMixer.removeTap(onBus: 0)
        self.activeGraph = nil
    }
    
    /// Сбор снимков измерений с частотой 25 Гц (каждые 40 мс)
    public func pollSnapshots() {
        PerformanceSignposts.shared.emitEvent("MeteringSnapshotDispatch")
        self.backingMeter = backingProcessor.updateSnapshot()
        self.mic1Meter = mic1Processor.updateSnapshot()
        self.mic2Meter = mic2Processor.updateSnapshot()
        self.fohMeter = fohProcessor.updateSnapshot()
        self.iemMeter = iemProcessor.updateSnapshot()
    }
    
    private func startSnapshotTimer() {
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollSnapshots()
            }
        }
    }
    
    isolated deinit {
        snapshotTimer?.invalidate()
    }
}
