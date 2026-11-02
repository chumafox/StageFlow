import Foundation
import AVFoundation

/// Backend реализации AVAudioPlayerNode по умолчанию
@MainActor
public final class AVAudioPlayerNodeBackend: AudioPlayerBackend {
    public let playerNode: AVAudioPlayerNode
    
    public init(playerNode: AVAudioPlayerNode) {
        self.playerNode = playerNode
    }
    
    public var isNodePlaying: Bool {
        playerNode.isPlaying
    }
    
    public func play() {
        guard let engine = playerNode.engine, engine.isRunning else { return }
        guard !playerNode.isPlaying else { return }
        playerNode.play()
    }
    
    public func pause() {
        guard playerNode.isPlaying else { return }
        playerNode.pause()
    }
    
    public func stop() {
        playerNode.stop()
    }
    
    public func scheduleSegment(
        file: AVAudioFile,
        startingFrame: AVAudioFramePosition,
        frameCount: AVAudioFrameCount,
        at when: AVAudioTime?,
        completionHandler: (@Sendable () -> Void)?
    ) {
        playerNode.scheduleSegment(
            file,
            startingFrame: startingFrame,
            frameCount: frameCount,
            at: when,
            completionHandler: completionHandler
        )
    }
    
    public func scheduleBuffer(
        buffer: AVAudioPCMBuffer,
        at when: AVAudioTime?,
        options: AVAudioPlayerNodeBufferOptions,
        completionHandler: (@Sendable () -> Void)?
    ) {
        playerNode.scheduleBuffer(
            buffer,
            at: when,
            options: options,
            completionHandler: completionHandler
        )
    }
    
    public func currentRenderPosition() -> (sampleTime: AVAudioFramePosition, sampleRate: Double)? {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return nil
        }
        return (playerTime.sampleTime, playerTime.sampleRate)
    }
}

/// Контроллер аудио-транспорта с конечным автоматом, точным Seek, синхронным аудио-клоком и защитой от stale completions (E07 / ADR-003)
@MainActor
public final class TransportController: ObservableObject, TransportControllerProtocol {
    public let backend: AudioPlayerBackend
    
    // UI-состояние транспорта
    @Published public private(set) var state: TransportState = .stopped
    @Published public private(set) var currentTrackTime: TimeInterval = 0.0
    @Published public private(set) var trackDuration: TimeInterval = 0.0
    
    // Единственный источник правды для UI ON AIR
    public var isPlaying: Bool {
        state == .playing
    }
    
    // Хранение активного источника (E07.2)
    public private(set) var currentURL: URL?
    public private(set) var currentAudioFile: AVAudioFile?
    public private(set) var lastError: StageFlowError?
    private var currentBuffer: AVAudioPCMBuffer?
    private var currentSampleRate: Double = 48000.0
    private var currentTotalFrames: AVAudioFramePosition = 0
    
    // Внутренний аудио-клок (E07.5)
    private var startOffsetTime: TimeInterval = 0.0
    private var lastKnownTime: TimeInterval = 0.0
    
    // Монотонный токен операции для исключения stale callbacks (E07.7)
    private var currentOperationID: UInt64 = 0
    
    public convenience init(playerNode: AVAudioPlayerNode) {
        self.init(backend: AVAudioPlayerNodeBackend(playerNode: playerNode))
    }
    
    public init(backend: AudioPlayerBackend) {
        self.backend = backend
    }
    
    // MARK: - Загрузка источника (E07.2 / E07.8)
    
    public func loadAudioFile(url: URL) {
        let signpost = PerformanceSignposts.shared.beginInterval("AudioFileLoad")
        defer { PerformanceSignposts.shared.endInterval("AudioFileLoad", state: signpost) }
        
        currentOperationID += 1
        let opID = currentOperationID
        
        backend.stop()
        state = .loading(url)
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            let err = StageFlowError.missingFile(url.lastPathComponent)
            self.lastError = err
            self.currentAudioFile = nil
            self.currentURL = nil
            self.currentBuffer = nil
            self.trackDuration = 0.0
            self.currentTrackTime = 0.0
            self.state = .failed(err)
            return
        }
        
        do {
            let file: AVAudioFile
            do {
                file = try AVAudioFile(forReading: url)
            } catch {
                let nsErr = error as NSError
                if nsErr.domain == NSOSStatusErrorDomain {
                    throw StageFlowError.corruptFile("Cannot decode audio file \(url.lastPathComponent): \(error.localizedDescription)")
                } else {
                    throw StageFlowError.unsupportedFileType("Unsupported audio format for \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            
            let format = file.processingFormat
            guard format.sampleRate > 0, file.length > 0 else {
                throw StageFlowError.corruptFile("Invalid audio format or empty file: \(url.lastPathComponent)")
            }
            
            self.currentAudioFile = file
            self.currentURL = url
            self.currentBuffer = nil
            self.currentSampleRate = format.sampleRate
            self.currentTotalFrames = file.length
            self.trackDuration = Double(file.length) / format.sampleRate
            self.currentTrackTime = 0.0
            self.startOffsetTime = 0.0
            self.lastKnownTime = 0.0
            self.lastError = nil
            
            // Планируем начальный сегмент с 0 фрейма
            backend.scheduleSegment(
                file: file,
                startingFrame: 0,
                frameCount: AVAudioFrameCount(file.length),
                at: nil
            ) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self, self.currentOperationID == opID else { return }
                    guard self.state == .playing else { return }
                    self.handleNaturalEOF()
                }
            }
            
            // Внимание: Autoplay запрещён! (E07.1 / ADR-003)
            self.state = .ready(url)
        } catch let err as StageFlowError {
            self.currentAudioFile = nil
            self.currentURL = nil
            self.currentBuffer = nil
            self.trackDuration = 0.0
            self.currentTrackTime = 0.0
            self.lastError = err
            self.state = .failed(err)
        } catch {
            let err = StageFlowError.corruptFile(error.localizedDescription)
            self.currentAudioFile = nil
            self.currentURL = nil
            self.currentBuffer = nil
            self.trackDuration = 0.0
            self.currentTrackTime = 0.0
            self.lastError = err
            self.state = .failed(err)
        }
    }
    
    public func loadDemoBuffer(buffer: AVAudioPCMBuffer, duration: TimeInterval) {
        currentOperationID += 1
        if backend.isNodePlaying {
            backend.stop()
        }
        
        self.currentAudioFile = nil
        self.currentURL = nil
        self.currentBuffer = buffer
        self.currentSampleRate = buffer.format.sampleRate
        self.currentTotalFrames = AVAudioFramePosition(buffer.frameLength)
        self.trackDuration = duration
        self.currentTrackTime = 0.0
        self.startOffsetTime = 0.0
        self.lastKnownTime = 0.0
        
        backend.scheduleBuffer(buffer: buffer, at: nil, options: .loops, completionHandler: nil)
        self.state = .stopped
    }
    
    // MARK: - Управление воспроизведением
    
    public func play() {
        // Блокировка воспроизведения при ошибке или отсутствии источника (E08.4)
        switch state {
        case .failed, .loading:
            return
        case .playing:
            return
        case .ended:
            seek(to: 0.0)
            backend.play()
            state = .playing
        case .stopped:
            guard currentAudioFile != nil || currentBuffer != nil else { return }
            backend.play()
            state = .playing
        case .ready:
            backend.play()
            state = .playing
        case .paused:
            backend.play()
            state = .playing
        }
    }
    
    public func pause() {
        guard state == .playing else { return }
        let now = currentAudioPosition()
        currentTrackTime = now
        startOffsetTime = now
        lastKnownTime = now
        backend.pause()
        state = .paused
    }
    
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    public func stop() {
        currentOperationID += 1
        let opID = currentOperationID
        
        backend.stop()
        currentTrackTime = 0.0
        startOffsetTime = 0.0
        lastKnownTime = 0.0
        
        if let file = currentAudioFile {
            // Гарантия E07.2: Stop никогда не подменяет пользовательский файл demo-буфером!
            backend.scheduleSegment(
                file: file,
                startingFrame: 0,
                frameCount: AVAudioFrameCount(file.length),
                at: nil
            ) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self, self.currentOperationID == opID else { return }
                    guard self.state == .playing else { return }
                    self.handleNaturalEOF()
                }
            }
            state = .stopped
        } else if let buffer = currentBuffer {
            backend.scheduleBuffer(buffer: buffer, at: nil, options: .loops, completionHandler: nil)
            state = .stopped
        } else {
            state = .stopped
        }
    }
    
    // MARK: - Настоящий Seek (E07.3 / E07.4)
    
    public func seek(to targetTime: TimeInterval) {
        PerformanceSignposts.shared.emitEvent("TransportSeek")
        let clampedTime = max(0.0, min(targetTime, trackDuration))
        
        if let file = currentAudioFile {
            let targetFrame = AVAudioFramePosition(clampedTime * currentSampleRate)
            let boundedFrame = max(0, min(targetFrame, currentTotalFrames))
            
            if boundedFrame >= currentTotalFrames && trackDuration > 0 {
                handleNaturalEOF()
                return
            }
            
            currentOperationID += 1
            let opID = currentOperationID
            
            let actualOffset = Double(boundedFrame) / currentSampleRate
            startOffsetTime = actualOffset
            currentTrackTime = actualOffset
            lastKnownTime = actualOffset
            
            let remainingFrames = AVAudioFrameCount(max(0, currentTotalFrames - boundedFrame))
            let wasPlaying = (state == .playing)
            
            backend.stop()
            backend.scheduleSegment(
                file: file,
                startingFrame: boundedFrame,
                frameCount: remainingFrames,
                at: nil
            ) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self, self.currentOperationID == opID else { return }
                    guard self.state == .playing else { return }
                    self.handleNaturalEOF()
                }
            }
            
            if wasPlaying {
                backend.play()
                state = .playing
            }
        } else {
            // Режим демо-буфера или без файла
            startOffsetTime = clampedTime
            currentTrackTime = clampedTime
            lastKnownTime = clampedTime
        }
    }
    
    // MARK: - Audio Clock & Display Sync (E07.5)
    
    public func pollAndUpdateDisplay() {
        self.currentTrackTime = currentAudioPosition()
    }
    
    public func currentAudioPosition() -> TimeInterval {
        switch state {
        case .playing:
            if let (sampleTime, sampleRate) = backend.currentRenderPosition(), sampleRate > 0, sampleTime >= 0 {
                let elapsed = Double(sampleTime) / sampleRate
                let pos = min(trackDuration, max(0.0, startOffsetTime + elapsed))
                lastKnownTime = pos
                return pos
            } else {
                return lastKnownTime
            }
        case .paused, .stopped, .ready, .loading, .failed:
            return currentTrackTime
        case .ended:
            return trackDuration
        }
    }
    
    // MARK: - Завершение воспроизведения (E07.6)
    
    private func handleNaturalEOF() {
        state = .ended
        currentTrackTime = trackDuration
        lastKnownTime = trackDuration
        backend.stop()
    }
}
