import Foundation
import AVFoundation

/// Конечный автомат состояний аудио-транспорта (E07.1 / ADR-003 / E08.1)
public enum TransportState: Equatable, Sendable {
    case stopped
    case loading(URL)
    case ready(URL)
    case playing
    case paused
    case ended
    case failed(StageFlowError)
}

/// Протокол аппаратных аудиочасов для обеспечения независимости от системного таймера
public protocol AudioClockProtocol: Sendable {
    func currentAudioTime() -> TimeInterval
}

/// Протокол абстракции воспроизведения для тестируемости и независимости от CoreAudio hardware
@MainActor
public protocol AudioPlayerBackend: AnyObject {
    var isNodePlaying: Bool { get }
    func play()
    func pause()
    func stop()
    func scheduleSegment(
        file: AVAudioFile,
        startingFrame: AVAudioFramePosition,
        frameCount: AVAudioFrameCount,
        at when: AVAudioTime?,
        completionHandler: (@Sendable () -> Void)?
    )
    func scheduleBuffer(
        buffer: AVAudioPCMBuffer,
        at when: AVAudioTime?,
        options: AVAudioPlayerNodeBufferOptions,
        completionHandler: (@Sendable () -> Void)?
    )
    func currentRenderPosition() -> (sampleTime: AVAudioFramePosition, sampleRate: Double)?
}

/// Протокол управления транспортом аудио
@MainActor
public protocol TransportControllerProtocol: AnyObject {
    var state: TransportState { get }
    var isPlaying: Bool { get }
    var currentTrackTime: TimeInterval { get }
    var trackDuration: TimeInterval { get }
    
    func loadAudioFile(url: URL)
    func play()
    func pause()
    func togglePlayPause()
    func stop()
    func seek(to time: TimeInterval)
}

/// Протокол хранилища MIDI-маппингов
public protocol MIDIMappingStoreProtocol: Sendable {
    func mapping(forChannel channel: UInt8, cc: UInt8) -> MIDIMapping?
    func saveMapping(_ mapping: MIDIMapping)
    func allMappings() -> [MIDIMapping]
}

/// Протокол асинхронного импорта треков (E11.1 / E11.3)
public protocol TrackImporterProtocol: Sendable {
    func importTrack(from url: URL) async throws -> SongTrack
    func importBatch(
        urls: [URL],
        maxConcurrency: Int,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async -> (tracks: [SongTrack], errors: [(url: URL, error: StageFlowError)])
}

/// Снимок данных сета и плейлиста для персистентного хранения (E11.5 / E11.9)
public struct SetlistData: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var tracks: [SongTrack]
    public var selectedTrackID: UUID?
    public var prompterFontSize: Double
    public var autoScrollEnabled: Bool
    public var midiMappings: [MIDIMapping]
    
    public init(
        schemaVersion: Int = 1,
        tracks: [SongTrack] = [],
        selectedTrackID: UUID? = nil,
        prompterFontSize: Double = 28.0,
        autoScrollEnabled: Bool = true,
        midiMappings: [MIDIMapping] = []
    ) {
        self.schemaVersion = schemaVersion
        self.tracks = tracks
        self.selectedTrackID = selectedTrackID
        self.prompterFontSize = prompterFontSize
        self.autoScrollEnabled = autoScrollEnabled
        self.midiMappings = midiMappings
    }
}

/// Протокол атомарного хранилища плейлиста и настроек (E11.5 / E11.6)
public protocol SetlistStoreProtocol: Sendable {
    func save(setlist: SetlistData) throws
    func load() -> SetlistData?
}
