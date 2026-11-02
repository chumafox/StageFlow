import Testing
import Foundation
import AVFoundation
@testable import StageFlow

@Suite("E11 Import, Playlist & Persistence Tests")
struct SetlistPersistenceTests {
    
    // Helper to generate temporary valid PCM WAV files efficiently
    private func createTestWAVFile(namePrefix: String = "track", duration: Double = 3.5, sampleRate: Double = 44100.0) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(namePrefix)_\(UUID().uuidString).wav")
        
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false)!
        let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        chunk.frameLength = frameCount
        try file.write(from: chunk)
        
        return fileURL
    }
    
    // MARK: - E11.1 / E11.2: Real duration and track import
    
    @Test("TrackImporter calculates real duration and metadata without hardcoded 180s (E11.1 / E11.2 / SF-11)")
    func testTrackImporterRealDuration() async throws {
        let durationTarget = 4.25
        let fileURL = try createTestWAVFile(namePrefix: "RockSong", duration: durationTarget)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        
        let importer = TrackImporter()
        let track = try await importer.importTrack(from: fileURL)
        
        #expect(abs(track.duration - durationTarget) < 0.1)
        #expect(track.duration != 180.0) // SF-11 fix
        #expect(track.title.contains("RockSong"))
        #expect(track.isAvailable == true)
        #expect(track.fileURL == fileURL)
    }
    
    // MARK: - E11.3: Responsive batch import with progress & error isolation
    
    private final class ProgressTracker: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var values: [Double] = []
        func append(_ val: Double) {
            lock.lock()
            defer { lock.unlock() }
            values.append(val)
        }
        var last: Double? {
            lock.lock()
            defer { lock.unlock() }
            return values.last
        }
    }
    
    @Test("Batch import processes files concurrently, tracks progress, and isolates per-file errors (E11.3)")
    func testBatchImportWithErrors() async throws {
        let url1 = try createTestWAVFile(namePrefix: "Batch1", duration: 1.0)
        let url2 = try createTestWAVFile(namePrefix: "Batch2", duration: 2.0)
        let corruptURL = FileManager.default.temporaryDirectory.appendingPathComponent("corrupt_\(UUID().uuidString).wav")
        try Data([0x00, 0x01, 0x02]).write(to: corruptURL)
        let missingURL = FileManager.default.temporaryDirectory.appendingPathComponent("missing_\(UUID().uuidString).wav")
        
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
            try? FileManager.default.removeItem(at: corruptURL)
        }
        
        let importer = TrackImporter()
        let tracker = ProgressTracker()
        
        let result = await importer.importBatch(
            urls: [url1, corruptURL, url2, missingURL],
            maxConcurrency: 2
        ) { progress in
            tracker.append(progress)
        }
        
        // 2 успешных трека
        #expect(result.tracks.count == 2)
        #expect(result.tracks[0].title.contains("Batch1"))
        #expect(result.tracks[1].title.contains("Batch2"))
        
        // 2 изолированные ошибки
        #expect(result.errors.count == 2)
        #expect(result.errors.contains { $0.url == corruptURL })
        #expect(result.errors.contains { $0.url == missingURL })
        
        // Прогресс дошёл до 100%
        #expect(tracker.last == 1.0)
    }
    
    // MARK: - E11.1 / E11.10: Format validation
    
    @Test("Unsupported file format throws typed StageFlowError (E11.1 / E11.10)")
    func testUnsupportedFormat() async throws {
        let txtURL = FileManager.default.temporaryDirectory.appendingPathComponent("sample_\(UUID().uuidString).pdf")
        try Data("dummy".utf8).write(to: txtURL)
        defer { try? FileManager.default.removeItem(at: txtURL) }
        
        let importer = TrackImporter()
        do {
            _ = try await importer.importTrack(from: txtURL)
            Issue.record("Expected unsupportedFileType error, but succeeded")
        } catch let error as StageFlowError {
            guard case .unsupportedFileType = error else {
                Issue.record("Expected .unsupportedFileType, got \(error)")
                return
            }
        }
    }
    
    // MARK: - E11.5 / E11.6 / E11.9: Setlist store atomic persistence
    
    @Test("SetlistStore saves atomically, restores schema v1, tracks, selection, prompter and mappings (E11.5 / E11.6 / E11.9)")
    func testSetlistAtomicSaveAndLoad() throws {
        let tempStoreURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_setlist_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempStoreURL) }
        
        let store = SetlistStore(storageURL: tempStoreURL)
        
        let track1 = SongTrack(title: "Track One", artist: "Artist A", duration: 120.0)
        let track2 = SongTrack(title: "Track Two", artist: "Artist B", duration: 240.0)
        let mapping = MIDIMapping(
            name: "Master Fader",
            trigger: .controlChange(channel: 0, cc: 7),
            target: .masterFOH
        )
        
        let initialData = SetlistData(
            schemaVersion: 1,
            tracks: [track1, track2],
            selectedTrackID: track2.id,
            prompterFontSize: 36.0,
            autoScrollEnabled: false,
            midiMappings: [mapping]
        )
        
        try store.save(setlist: initialData)
        #expect(FileManager.default.fileExists(atPath: tempStoreURL.path))
        
        // Загрузка отдельным экземпляром (симуляция перезапуска приложения)
        let loadedStore = SetlistStore(storageURL: tempStoreURL)
        let loaded = loadedStore.load()
        
        #expect(loaded != nil)
        #expect(loaded?.schemaVersion == 1)
        #expect(loaded?.tracks.count == 2)
        #expect(loaded?.tracks[0].title == "Track One")
        #expect(loaded?.tracks[1].title == "Track Two")
        #expect(loaded?.selectedTrackID == track2.id)
        #expect(loaded?.prompterFontSize == 36.0)
        #expect(loaded?.autoScrollEnabled == false)
        #expect(loaded?.midiMappings.count == 1)
        #expect(loaded?.midiMappings[0].target == .masterFOH)
    }
    
    // MARK: - E11.6 / E11.10: Corrupt JSON graceful recovery
    
    @Test("Corrupted store file creates backup and returns nil without crash (E11.6 / E11.10)")
    func testCorruptStoreRecovery() throws {
        let tempStoreURL = FileManager.default.temporaryDirectory.appendingPathComponent("corrupt_store_\(UUID().uuidString).json")
        try Data("{ invalid json, corrupted data ...".utf8).write(to: tempStoreURL)
        defer {
            try? FileManager.default.removeItem(at: tempStoreURL)
            // Очистка бэкапов
            let parent = tempStoreURL.deletingLastPathComponent()
            let files = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
            for f in files where f.contains("setlist.corrupt.") {
                try? FileManager.default.removeItem(at: parent.appendingPathComponent(f))
            }
        }
        
        let store = SetlistStore(storageURL: tempStoreURL)
        let result = store.load()
        
        #expect(result == nil)
        
        // Проверяем, что был создан аварийный бэкап
        let parent = tempStoreURL.deletingLastPathComponent()
        let files = try FileManager.default.contentsOfDirectory(atPath: parent.path)
        let backupExists = files.contains { $0.contains("setlist.corrupt.") }
        #expect(backupExists == true)
    }
    
    // MARK: - E11.7: Missing and moved files detection
    
    @Test("Deleted audio file is preserved in setlist and marked as unavailable without deletion (E11.7)")
    func testMissingFilePreservedAsUnavailable() throws {
        let tempStoreURL = FileManager.default.temporaryDirectory.appendingPathComponent("missing_store_\(UUID().uuidString).json")
        let audioURL = try createTestWAVFile(namePrefix: "TemporaryAudio")
        
        let store = SetlistStore(storageURL: tempStoreURL)
        let track = SongTrack(title: "Temporary Song", fileURL: audioURL, duration: 10.0, isAvailable: true)
        let setlist = SetlistData(tracks: [track], selectedTrackID: track.id)
        try store.save(setlist: setlist)
        
        // Удаляем физический файл (симуляция удаления или переименования папки)
        try FileManager.default.removeItem(at: audioURL)
        defer { try? FileManager.default.removeItem(at: tempStoreURL) }
        
        // При повторной загрузке трек обязан остаться в плейлисте, но помечен недоступным
        let reloaded = store.load()
        #expect(reloaded != nil)
        #expect(reloaded?.tracks.count == 1)
        #expect(reloaded?.tracks[0].title == "Temporary Song")
        #expect(reloaded?.tracks[0].isAvailable == false)
    }
    
    // MARK: - E11.4 / E11.7: Relink missing file
    
    @Test("Relinking unavailable track updates URL, duration, availability and persists changes (E11.4 / E11.7)")
    @MainActor
    func testRelinkTrack() async throws {
        let tempStoreURL = FileManager.default.temporaryDirectory.appendingPathComponent("relink_store_\(UUID().uuidString).json")
        let store = SetlistStore(storageURL: tempStoreURL)
        defer { try? FileManager.default.removeItem(at: tempStoreURL) }
        
        let missingURL = URL(fileURLWithPath: "/tmp/non_existent_file_\(UUID().uuidString).wav")
        let track = SongTrack(title: "Missing Song", fileURL: missingURL, duration: 0.0, isAvailable: false)
        
        let appState = AppState(setlistStore: store, autoLoad: false)
        appState.playlist = [track]
        appState.selectedTrackID = track.id
        
        // Создаем новый реальный файл для релинка
        let replacementURL = try createTestWAVFile(namePrefix: "Replacement", duration: 7.5)
        defer { try? FileManager.default.removeItem(at: replacementURL) }
        
        await appState.relinkTrack(id: track.id, newURL: replacementURL)
        
        #expect(appState.playlist[0].isAvailable == true)
        #expect(appState.playlist[0].fileURL?.resolvingSymlinksInPath().path == replacementURL.resolvingSymlinksInPath().path)
        #expect(abs(appState.playlist[0].duration - 7.5) < 0.1)
        
        // Проверяем, что в сохранённом на диск store изменения тоже зафиксированы
        let loaded = store.load()
        #expect(loaded?.tracks[0].isAvailable == true)
        #expect(loaded?.tracks[0].fileURL?.resolvingSymlinksInPath().path == replacementURL.resolvingSymlinksInPath().path)
    }
    
    // MARK: - E11.4: Remove track updates selection
    
    @Test("Removing selected track selects adjacent track and saves state (E11.4)")
    @MainActor
    func testRemoveTrackSelectionHandling() throws {
        let tempStoreURL = FileManager.default.temporaryDirectory.appendingPathComponent("remove_store_\(UUID().uuidString).json")
        let store = SetlistStore(storageURL: tempStoreURL)
        defer { try? FileManager.default.removeItem(at: tempStoreURL) }
        
        let track1 = SongTrack(title: "Song 1")
        let track2 = SongTrack(title: "Song 2")
        let track3 = SongTrack(title: "Song 3")
        
        let appState = AppState(setlistStore: store, autoLoad: false)
        appState.playlist = [track1, track2, track3]
        appState.selectTrack(track2)
        #expect(appState.selectedTrackID == track2.id)
        
        // Удаляем выбранный средний трек
        appState.removeTrack(id: track2.id)
        
        #expect(appState.playlist.count == 2)
        #expect(appState.selectedTrackID == track3.id)
        
        // Удаляем последний
        appState.removeTrack(id: track3.id)
        #expect(appState.playlist.count == 1)
        #expect(appState.selectedTrackID == track1.id)
    }
}
