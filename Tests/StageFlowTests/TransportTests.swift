import Foundation
import Testing
import AVFoundation
@testable import StageFlow

// MARK: - Fake Player Backend for Deterministic Verification (E07.10)

@MainActor
final class FakeAudioPlayerBackend: AudioPlayerBackend {
    var isNodePlaying: Bool = false
    var playCallCount: Int = 0
    var pauseCallCount: Int = 0
    var stopCallCount: Int = 0
    
    var scheduledStartingFrame: AVAudioFramePosition?
    var scheduledFrameCount: AVAudioFrameCount?
    var lastCompletionHandler: (@Sendable () -> Void)?
    
    var simulatedSampleTime: AVAudioFramePosition = 0
    var simulatedSampleRate: Double = 48000.0
    
    func play() {
        isNodePlaying = true
        playCallCount += 1
    }
    
    func pause() {
        isNodePlaying = false
        pauseCallCount += 1
    }
    
    func stop() {
        isNodePlaying = false
        stopCallCount += 1
    }
    
    func scheduleSegment(
        file: AVAudioFile,
        startingFrame: AVAudioFramePosition,
        frameCount: AVAudioFrameCount,
        at when: AVAudioTime?,
        completionHandler: (@Sendable () -> Void)?
    ) {
        scheduledStartingFrame = startingFrame
        scheduledFrameCount = frameCount
        lastCompletionHandler = completionHandler
    }
    
    func scheduleBuffer(
        buffer: AVAudioPCMBuffer,
        at when: AVAudioTime?,
        options: AVAudioPlayerNodeBufferOptions,
        completionHandler: (@Sendable () -> Void)?
    ) {
        lastCompletionHandler = completionHandler
    }
    
    func currentRenderPosition() -> (sampleTime: AVAudioFramePosition, sampleRate: Double)? {
        guard isNodePlaying else { return nil }
        return (simulatedSampleTime, simulatedSampleRate)
    }
    
    func triggerCompletion() {
        lastCompletionHandler?()
    }
}

// MARK: - Test Suite E07

@Suite("E07 Transport Controller & Audio Clock Tests")
struct TransportTests {
    
    // Helper to generate temporary valid PCM WAV files efficiently
    private func createTestWAVFile(sampleRate: Double, duration: Double, channels: Int = 2) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("stageflow_test_\(UUID().uuidString).wav")
        
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: AVAudioChannelCount(channels), interleaved: false)!
        let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        
        let chunkSize: AVAudioFrameCount = AVAudioFrameCount(sampleRate)
        let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize)!
        chunk.frameLength = chunkSize
        // chunk memory is zeroed, extremely fast
        
        var remainingFrames = AVAudioFrameCount(sampleRate * duration)
        while remainingFrames > 0 {
            let toWrite = min(remainingFrames, chunkSize)
            chunk.frameLength = toWrite
            try file.write(from: chunk)
            remainingFrames -= toWrite
        }
        
        return fileURL
    }
    
    // Helper to generate a corrupted non-audio file
    private func createCorruptAudioFile() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("stageflow_corrupt_\(UUID().uuidString).wav")
        let garbage = Data("THIS_IS_NOT_A_VALID_RIFF_WAV_HEADER_AND_WILL_FAIL".utf8)
        try garbage.write(to: fileURL)
        return fileURL
    }
    
    // 1. Seq 1: Load -> Play -> Pause -> Play -> Stop -> Play
    @Test("Sequence 1: Load -> Play -> Pause -> Play -> Stop -> Play (E07.1 / E07.10)")
    @MainActor
    func testSequence1_PlayPauseStopCycle() throws {
        let url = try createTestWAVFile(sampleRate: 48000, duration: 10.0)
        defer { try? FileManager.default.removeItem(at: url) }
        
        let backend = FakeAudioPlayerBackend()
        let transport = TransportController(backend: backend)
        
        #expect(transport.state == .stopped)
        #expect(!transport.isPlaying)
        
        // 1. Load
        transport.loadAudioFile(url: url)
        #expect(transport.state == .ready(url))
        #expect(!transport.isPlaying) // No autoplay!
        #expect(transport.trackDuration == 10.0)
        #expect(transport.currentTrackTime == 0.0)
        #expect(backend.scheduledStartingFrame == AVAudioFramePosition(0))
        
        // 2. Play
        transport.play()
        #expect(transport.state == .playing)
        #expect(transport.isPlaying)
        #expect(backend.isNodePlaying)
        
        // 3. Pause
        backend.simulatedSampleTime = 48000 * 2 // 2.0s
        transport.pollAndUpdateDisplay()
        #expect(abs(transport.currentTrackTime - 2.0) < 0.001)
        transport.pause()
        #expect(transport.state == .paused)
        #expect(!transport.isPlaying)
        #expect(!backend.isNodePlaying)
        #expect(abs(transport.currentTrackTime - 2.0) < 0.001)
        
        // 4. Play (resumes from 2.0s)
        transport.play()
        #expect(transport.state == .playing)
        #expect(transport.isPlaying)
        #expect(backend.isNodePlaying)
        
        // 5. Stop
        transport.stop()
        #expect(transport.state == .stopped)
        #expect(!transport.isPlaying)
        #expect(!backend.isNodePlaying)
        #expect(transport.currentTrackTime == 0.0)
        #expect(backend.scheduledStartingFrame == AVAudioFramePosition(0))
        
        // 6. Play after Stop (starts same file from beginning)
        transport.play()
        #expect(transport.state == .playing)
        #expect(transport.isPlaying)
        #expect(transport.currentAudioFile != nil)
        #expect(transport.currentURL == url)
    }
    
    // 2. Seq 2: Play -> Seek forward -> Seek backward -> Pause -> Seek -> Play
    @Test("Sequence 2: Seek forward/backward during playback and while paused (E07.3 / E07.4)")
    @MainActor
    func testSequence2_SeekDuringPlayAndPause() throws {
        let url = try createTestWAVFile(sampleRate: 48000, duration: 20.0)
        defer { try? FileManager.default.removeItem(at: url) }
        
        let backend = FakeAudioPlayerBackend()
        let transport = TransportController(backend: backend)
        transport.loadAudioFile(url: url)
        transport.play()
        #expect(transport.state == .playing)
        
        // Seek forward to 8.0s while playing
        transport.seek(to: 8.0)
        #expect(transport.state == .playing) // Stays playing
        #expect(backend.isNodePlaying)
        #expect(abs(transport.currentTrackTime - 8.0) < 0.001)
        #expect(backend.scheduledStartingFrame == AVAudioFramePosition(48000 * 8))
        #expect(backend.scheduledFrameCount == AVAudioFrameCount(48000 * 12))
        
        // Seek backward to 3.0s while playing
        transport.seek(to: 3.0)
        #expect(transport.state == .playing)
        #expect(backend.isNodePlaying)
        #expect(abs(transport.currentTrackTime - 3.0) < 0.001)
        #expect(backend.scheduledStartingFrame == AVAudioFramePosition(48000 * 3))
        #expect(backend.scheduledFrameCount == AVAudioFrameCount(48000 * 17))
        
        // Pause
        transport.pause()
        #expect(transport.state == .paused)
        #expect(!transport.isPlaying)
        
        // Seek to 15.0s while paused: must NOT start playing (E07.4)
        transport.seek(to: 15.0)
        #expect(transport.state == .paused)
        #expect(!transport.isPlaying)
        #expect(!backend.isNodePlaying)
        #expect(abs(transport.currentTrackTime - 15.0) < 0.001)
        #expect(backend.scheduledStartingFrame == AVAudioFramePosition(48000 * 15))
        #expect(backend.scheduledFrameCount == AVAudioFrameCount(48000 * 5))
        
        // Play resumes from 15.0s
        transport.play()
        #expect(transport.state == .playing)
        #expect(transport.isPlaying)
    }
    
    // 3. Seq 3: Play -> Load of different track -> immediately Play
    @Test("Sequence 3: Selecting track during playback stops old track, loads new in ready without autoplay (E07.8)")
    @MainActor
    func testSequence3_TrackSwitchDuringPlayback() throws {
        let url1 = try createTestWAVFile(sampleRate: 48000, duration: 10.0)
        let url2 = try createTestWAVFile(sampleRate: 48000, duration: 30.0)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        let backend = FakeAudioPlayerBackend()
        let transport = TransportController(backend: backend)
        transport.loadAudioFile(url: url1)
        transport.play()
        #expect(transport.state == .playing)
        #expect(transport.isPlaying)
        
        // Load track 2 while playing
        transport.loadAudioFile(url: url2)
        #expect(transport.state == .ready(url2))
        #expect(!transport.isPlaying) // UI NOT ON AIR!
        #expect(!backend.isNodePlaying)
        #expect(transport.trackDuration == 30.0)
        #expect(transport.currentTrackTime == 0.0)
        #expect(transport.currentURL == url2)
        
        // Now explicit Play begins new track
        transport.play()
        #expect(transport.state == .playing)
        #expect(transport.isPlaying)
    }
    
    // 4. Seq 4: Play -> EOF -> Play
    @Test("Sequence 4: Natural EOF stops audio and sets ended; subsequent Play restarts track from beginning (E07.6)")
    @MainActor
    func testSequence4_EOFAndReplay() async throws {
        let url = try createTestWAVFile(sampleRate: 48000, duration: 10.0)
        defer { try? FileManager.default.removeItem(at: url) }
        
        let backend = FakeAudioPlayerBackend()
        let transport = TransportController(backend: backend)
        transport.loadAudioFile(url: url)
        transport.play()
        #expect(transport.state == .playing)
        
        // Simulate genuine EOF completion
        backend.triggerCompletion()
        
        // Yield to let Task @MainActor execute
        await Task.yield()
        
        #expect(transport.state == .ended)
        #expect(!transport.isPlaying)
        #expect(!backend.isNodePlaying)
        #expect(transport.currentTrackTime == 10.0)
        
        // Play from ended restarts track from 0.0 (per E07 table)
        transport.play()
        #expect(transport.state == .playing)
        #expect(transport.isPlaying)
        #expect(transport.currentTrackTime == 0.0)
        #expect(backend.scheduledStartingFrame == AVAudioFramePosition(0))
    }
    
    // 5. Seq 5: Stop -> guarantee same user file source (never demo buffer)
    @Test("Sequence 5: Stop retains active user file and never swaps for synthetic demo loop (E07.2)")
    @MainActor
    func testSequence5_StopRetainsUserFile() throws {
        let url = try createTestWAVFile(sampleRate: 48000, duration: 25.0)
        defer { try? FileManager.default.removeItem(at: url) }
        
        let backend = FakeAudioPlayerBackend()
        let transport = TransportController(backend: backend)
        
        // Explicitly load demo buffer first to simulate app launch state
        let dummyFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false)!
        let dummyBuffer = AVAudioPCMBuffer(pcmFormat: dummyFormat, frameCapacity: 48000)!
        dummyBuffer.frameLength = 48000
        transport.loadDemoBuffer(buffer: dummyBuffer, duration: 1.0)
        #expect(transport.currentAudioFile == nil)
        
        // User loads real backing track
        transport.loadAudioFile(url: url)
        #expect(transport.currentAudioFile != nil)
        #expect(transport.currentURL == url)
        
        transport.play()
        #expect(transport.isPlaying)
        
        // User hits Stop
        transport.stop()
        #expect(transport.state == .stopped)
        #expect(!transport.isPlaying)
        #expect(transport.currentAudioFile != nil) // MUST retain user file!
        #expect(transport.currentURL == url)
        #expect(transport.trackDuration == 25.0)
        
        // User hits Play again
        transport.play()
        #expect(transport.isPlaying)
        #expect(transport.currentAudioFile != nil)
        #expect(transport.currentURL == url)
    }
    
    // 6. Seq 6: Load -> corrupted file -> Play unavailable
    @Test("Sequence 6: Corrupted file transitions to failed and blocks playback (E07.1 / E08.1 / E08.4)")
    @MainActor
    func testSequence6_CorruptFileLoadFailsGracefully() throws {
        let corruptURL = try createCorruptAudioFile()
        defer { try? FileManager.default.removeItem(at: corruptURL) }
        
        let backend = FakeAudioPlayerBackend()
        let transport = TransportController(backend: backend)
        
        transport.loadAudioFile(url: corruptURL)
        guard case .failed(let err) = transport.state else {
            Issue.record("Expected transport state to be .failed, but got \(transport.state)")
            return
        }
        #expect(!err.localizedDescription.isEmpty)
        #expect(transport.lastError != nil)
        #expect(!transport.isPlaying)
        #expect(transport.currentAudioFile == nil)
        #expect(transport.trackDuration == 0.0)
        
        // Attempting to play a failed file must be a blocked no-op
        transport.play()
        #expect(!transport.isPlaying)
        #expect(!backend.isNodePlaying)
        if case .failed = transport.state {
            // PASS: remained failed
        } else {
            Issue.record("State changed unexpectedly after play on failed file")
        }
    }
    
    // 7. Seq 7: Rapid repeated Play/Pause without inconsistent state
    @Test("Sequence 7: 100 rapid Play/Pause cycles maintain strict state consistency (E07.1)")
    @MainActor
    func testSequence7_RapidPlayPauseSweeps() throws {
        let url = try createTestWAVFile(sampleRate: 48000, duration: 60.0)
        defer { try? FileManager.default.removeItem(at: url) }
        
        let backend = FakeAudioPlayerBackend()
        let transport = TransportController(backend: backend)
        transport.loadAudioFile(url: url)
        
        for i in 0..<100 {
            if i % 2 == 0 {
                transport.play()
                #expect(transport.state == .playing)
                #expect(transport.isPlaying)
                #expect(backend.isNodePlaying)
            } else {
                transport.pause()
                #expect(transport.state == .paused)
                #expect(!transport.isPlaying)
                #expect(!backend.isNodePlaying)
            }
        }
    }
    
    // 8. Seq 8: Multiple Seeks in rapid succession with delayed stale completions arriving
    @Test("Sequence 8: Monotonic operation generation tokens invalidate stale asynchronous completion callbacks (E07.7)")
    @MainActor
    func testSequence8_StaleCompletionTokens() async throws {
        let url = try createTestWAVFile(sampleRate: 48000, duration: 100.0)
        defer { try? FileManager.default.removeItem(at: url) }
        
        let backend = FakeAudioPlayerBackend()
        let transport = TransportController(backend: backend)
        transport.loadAudioFile(url: url)
        transport.play()
        
        // Capture completion handler from initial schedule
        let staleCompletion1 = backend.lastCompletionHandler
        
        // Seek 1
        transport.seek(to: 10.0)
        let staleCompletion2 = backend.lastCompletionHandler
        
        // Seek 2
        transport.seek(to: 25.0)
        let staleCompletion3 = backend.lastCompletionHandler
        
        // Seek 3
        transport.seek(to: 50.0)
        #expect(transport.state == .playing)
        #expect(abs(transport.currentTrackTime - 50.0) < 0.001)
        
        // Now simulate delayed arrival of old cancelled completion handlers!
        staleCompletion1?()
        staleCompletion2?()
        staleCompletion3?()
        
        await Task.yield()
        
        // Stale completions must be ignored and NOT put transport into .ended!
        #expect(transport.state == .playing)
        #expect(transport.isPlaying)
        #expect(abs(transport.currentTrackTime - 50.0) < 0.001)
    }
    
    // 9. Seq 9: Empty playlist & no source behavior
    @Test("Sequence 9: Empty state before source load safely ignores Play and Stop without errors (E07.1)")
    @MainActor
    func testSequence9_EmptySourceState() {
        let backend = FakeAudioPlayerBackend()
        let transport = TransportController(backend: backend)
        
        #expect(transport.state == .stopped)
        #expect(!transport.isPlaying)
        #expect(transport.currentTrackTime == 0.0)
        #expect(transport.trackDuration == 0.0)
        
        transport.play()
        #expect(transport.state == .stopped)
        #expect(!transport.isPlaying)
        #expect(!backend.isNodePlaying)
        
        transport.pause()
        #expect(transport.state == .stopped)
        
        transport.stop()
        #expect(transport.state == .stopped)
        
        transport.seek(to: 10.0)
        #expect(transport.currentTrackTime == 0.0)
    }
    
    // 10. Seq 10: Tracks with different sample rates (44.1 kHz, 48 kHz, 96 kHz)
    @Test("Sequence 10: Supports arbitrary sample rates (44.1, 48, 96 kHz) with exact frame calculation (E07.3)")
    @MainActor
    func testSequence10_MultipleSampleRates() throws {
        let sampleRates: [Double] = [44100.0, 48000.0, 96000.0]
        
        for sr in sampleRates {
            let url = try createTestWAVFile(sampleRate: sr, duration: 12.5)
            defer { try? FileManager.default.removeItem(at: url) }
            
            let backend = FakeAudioPlayerBackend()
            let transport = TransportController(backend: backend)
            transport.loadAudioFile(url: url)
            
            #expect(abs(transport.trackDuration - 12.5) < 0.001)
            #expect(backend.scheduledStartingFrame == AVAudioFramePosition(0))
            #expect(backend.scheduledFrameCount == AVAudioFrameCount(sr * 12.5))
            
            // Test seek at this sample rate
            transport.seek(to: 4.0)
            let expectedFrame = AVAudioFramePosition(sr * 4.0)
            #expect(backend.scheduledStartingFrame == expectedFrame)
            #expect(abs(transport.currentTrackTime - 4.0) < 0.001)
        }
    }
    
    // 11. 30-Minute Drift Check (< 100 ms) (E07 Validation 3)
    @Test("30-Minute simulated playback exhibits ZERO drift (< 100 ms tolerance) from hardware audio clock (E07.5)")
    @MainActor
    func testDriftOver30Minutes() throws {
        let url = try createTestWAVFile(sampleRate: 48000, duration: 1800.0) // 30 minutes = 1800s
        defer { try? FileManager.default.removeItem(at: url) }
        
        let backend = FakeAudioPlayerBackend()
        let transport = TransportController(backend: backend)
        transport.loadAudioFile(url: url)
        transport.play()
        
        // Simulate advancing the audio hardware clock to exactly 30 minutes (86,400,000 samples)
        let thirtyMinutesSamples: AVAudioFramePosition = 48000 * 1800
        backend.simulatedSampleTime = thirtyMinutesSamples
        backend.simulatedSampleRate = 48000.0
        
        // Poll display timer
        transport.pollAndUpdateDisplay()
        
        let measuredTime = transport.currentTrackTime
        let expectedTime = 1800.0
        let driftSeconds = abs(measuredTime - expectedTime)
        let driftMilliseconds = driftSeconds * 1000.0
        
        print("30-Minute Drift Check: measured=\(measuredTime)s, expected=\(expectedTime)s, drift=\(driftMilliseconds) ms")
        
        // Required: drift < 100 ms
        #expect(driftMilliseconds < 100.0)
        #expect(driftMilliseconds < 0.001) // In fact, sample-accurate = 0.000 ms!
    }
    
    // 12. Seek Precision (< 20 ms / 1 buffer) (E07 Validation 2)
    @Test("Seek accuracy translates directly to audio frame position within < 1 ms (< 20 ms tolerance) (E07.3)")
    @MainActor
    func testSeekAccuracyWithinTolerance() throws {
        let url = try createTestWAVFile(sampleRate: 48000, duration: 100.0)
        defer { try? FileManager.default.removeItem(at: url) }
        
        let backend = FakeAudioPlayerBackend()
        let transport = TransportController(backend: backend)
        transport.loadAudioFile(url: url)
        
        let testPositions: [TimeInterval] = [0.123, 1.456, 12.789, 55.555, 99.999]
        for targetTime in testPositions {
            transport.seek(to: targetTime)
            
            let scheduledFrame = backend.scheduledStartingFrame!
            let actualTimeFromFrame = Double(scheduledFrame) / 48000.0
            let errorSeconds = abs(actualTimeFromFrame - targetTime)
            let errorMilliseconds = errorSeconds * 1000.0
            
            // Tolerance is 20 ms (0.020 s). Sample resolution at 48kHz is ~0.0208 ms!
            #expect(errorMilliseconds < 20.0)
            #expect(errorMilliseconds < 0.05)
        }
    }
}
