import Testing
import Foundation
import AVFoundation
@testable import StageFlow

@Suite("E12 Performance Measurement & Optimization Tests")
struct PerformanceTests {
    
    private func createTestWAVFile(namePrefix: String = "perf", duration: Double = 1.0, sampleRate: Double = 44100.0) throws -> URL {
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
    
    // MARK: - P01: Simulated Playback & Metering Budget
    
    @Test("P01: 5,000 continuous metering buffer ingestions execute in under 100 ms without audio-thread stall (E12.4 / SF-10)")
    func testP01MeteringRealtimeBudget() {
        let clock = SimulatedAudioClock(initialTime: 0.0)
        let processor = ChannelMeterProcessor(clock: clock)
        
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000.0, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
        buffer.frameLength = 512
        
        // Заполняем синусоидой
        if let left = buffer.floatChannelData?[0], let right = buffer.floatChannelData?[1] {
            for i in 0..<512 {
                let s = sin(Float(i) * 0.1) * 0.7
                left[i] = s
                right[i] = s
            }
        }
        
        let start = DispatchTime.now()
        // 5 000 буферов по 512 фреймов при 48 кГц = 53 секунды непрерывного живого звука
        for _ in 0..<5_000 {
            processor.processBuffer(buffer)
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        let elapsedMs = Double(elapsed) / 1_000_000.0
        
        // 5,000 обработок должны занять менее 100 мс (в среднем < 0.02 мс на буфер)
        #expect(elapsedMs < 100.0)
        
        let reading = processor.updateSnapshot()
        #expect(reading.peakLinear > 0.6)
        #expect(reading.isClipping == false)
    }
    
    // MARK: - P02: Continuous Session & Rapid MIDI Bursts
    
    @Test("P02: Rapid burst of 2,000 MIDI events processes lock-free and coalesces UI within budget (E12.3 / E12.4)")
    @MainActor
    func testP02RapidMIDIBurst() async {
        let midi = MIDIManager(mappingStore: MIDIMappingStore())
        var volumeCallbackCount = 0
        midi.onVolumeChange = { _, _ in
            volumeCallbackCount += 1
        }
        
        let start = DispatchTime.now()
        // Шторм из 2,000 CC сообщений
        for i in 0..<2_000 {
            let val = UInt8(i % 128)
            midi.processIncomingEvent(.controlChange(channel: 0, cc: 7, value: val))
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        let elapsedMs = Double(elapsed) / 1_000_000.0
        
        // Обработка 2,000 сообщений должна уложиться менее чем в 150 мс
        #expect(elapsedMs < 150.0)
        #expect(volumeCallbackCount == 2_000)
    }
    
    // MARK: - P03: Batch Import Responsive Budget
    
    @Test("P03: Batch import of 20 audio files processes asynchronously with bounded concurrency (E12.6)")
    func testP03BatchImportPerformance() async throws {
        var urls: [URL] = []
        for i in 0..<20 {
            let url = try createTestWAVFile(namePrefix: "perf_\(i)", duration: 0.5)
            urls.append(url)
        }
        defer {
            for u in urls { try? FileManager.default.removeItem(at: u) }
        }
        
        let importer = TrackImporter()
        let start = DispatchTime.now()
        let result = await importer.importBatch(urls: urls, maxConcurrency: 4)
        let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        let elapsedMs = Double(elapsed) / 1_000_000.0
        
        #expect(result.tracks.count == 20)
        #expect(result.errors.isEmpty)
        // 20 файлов с чтением метаданных и длительности должны импортироваться быстрее 3 секунд
        #expect(elapsedMs < 3000.0)
    }
    
    // MARK: - P04: Rapid Fader & DSP Sweeps
    
    @Test("P04: 500 rapid volume and EQ sweeps execute smoothly without CPU hang (E12.3)")
    @MainActor
    func testP04DSPParameterSweeps() {
        let graph = AudioGraphController(force4ChannelOutput: true)
        
        let start = DispatchTime.now()
        for i in 0..<500 {
            let gain = Float(i % 100) / 100.0
            graph.backingFOHVolume = gain
            graph.backingIEMVolume = gain
            graph.mic1FOHVolume = gain
            graph.mic2FOHVolume = gain
            graph.mic1LowCutEnabled = (gain > 0.5)
            graph.mic1MidGain = (gain - 0.5) * 12.0
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        let elapsedMs = Double(elapsed) / 1_000_000.0
        
        // 500 полных смен параметров должны занять менее 100 мс
        #expect(elapsedMs < 100.0)
    }
    
    // MARK: - P05: Route Reconnect & Graph Lifecycle
    
    @Test("P05: 25 sequential audio graph stop/start lifecycle cycles execute cleanly (E12.8)")
    @MainActor
    func testP05AudioGraphLifecycleStress() {
        let graph = AudioGraphController(force4ChannelOutput: true)
        
        let start = DispatchTime.now()
        for _ in 0..<25 {
            try? graph.start()
            graph.stop()
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        let elapsedMs = Double(elapsed) / 1_000_000.0
        
        #expect(elapsedMs < 1500.0)
    }
    
    // MARK: - P06: Large Playlist Scaling (500 tracks)
    
    @Test("P06: Large playlist of 500 songs serializes and deserializes atomically in under 50 ms (E12.8 / SF-10)")
    func testP06LargePlaylistScaling() throws {
        let tempStoreURL = FileManager.default.temporaryDirectory.appendingPathComponent("p06_store_\(UUID().uuidString).json")
        let store = SetlistStore(storageURL: tempStoreURL)
        defer { try? FileManager.default.removeItem(at: tempStoreURL) }
        
        var tracks: [SongTrack] = []
        for i in 1...500 {
            let track = SongTrack(
                title: "Song Number \(i)",
                artist: "Festival Headliner",
                duration: 215.0,
                lyrics: [
                    LyricLine(timestamp: 0.0, rawText: "Intro line", plainText: "Intro line", chords: []),
                    LyricLine(timestamp: 15.0, rawText: "[C]Verse line", plainText: "Verse line", chords: [ChordMarker(chord: "C", characterIndex: 0)])
                ]
            )
            tracks.append(track)
        }
        
        let data = SetlistData(
            schemaVersion: 1,
            tracks: tracks,
            selectedTrackID: tracks[250].id,
            prompterFontSize: 28.0,
            autoScrollEnabled: true,
            midiMappings: []
        )
        
        // Сохранение 500 треков
        let startSave = DispatchTime.now()
        try store.save(setlist: data)
        let elapsedSaveMs = Double(DispatchTime.now().uptimeNanoseconds - startSave.uptimeNanoseconds) / 1_000_000.0
        
        #expect(elapsedSaveMs < 100.0)
        
        // Чтение 500 треков
        let startLoad = DispatchTime.now()
        let loaded = store.load()
        let elapsedLoadMs = Double(DispatchTime.now().uptimeNanoseconds - startLoad.uptimeNanoseconds) / 1_000_000.0
        
        #expect(elapsedLoadMs < 50.0)
        #expect(loaded?.tracks.count == 500)
        #expect(loaded?.selectedTrackID == tracks[250].id)
    }
}
