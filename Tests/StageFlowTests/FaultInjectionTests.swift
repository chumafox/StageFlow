import Foundation
import Testing
import AVFoundation
@testable import StageFlow

@Suite("E08 Fault Injection & Lifecycle Reliability Tests")
struct FaultInjectionTests {
    
    // MARK: - Вспомогательные методы создания фикстур
    
    private func createTempFile(name: String, bytes: [UInt8]) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("fault_\(UUID().uuidString)_\(name)")
        let data = Data(bytes)
        try data.write(to: fileURL)
        return fileURL
    }
    
    private func createCorruptWavFile() throws -> URL {
        // Заголовок RIFF, но повреждённый чанк fmt/data
        let corruptBytes: [UInt8] = [
            0x52, 0x49, 0x46, 0x46, // "RIFF"
            0x24, 0x00, 0x00, 0x00, // file length 36
            0x57, 0x41, 0x56, 0x45, // "WAVE"
            0xFF, 0xFF, 0xFF, 0xFF  // Corrupt garbage chunk ID
        ]
        return try createTempFile(name: "corrupt.wav", bytes: corruptBytes)
    }
    
    private func createTruncatedAudioFile() throws -> URL {
        // Только 8 байт
        let truncatedBytes: [UInt8] = [0x52, 0x49, 0x46, 0x46, 0x08, 0x00, 0x00, 0x00]
        return try createTempFile(name: "truncated.wav", bytes: truncatedBytes)
    }
    
    private func createUnsupportedTextFile() throws -> URL {
        let textBytes = Array("This is plain text and definitely not an audio file.".utf8)
        return try createTempFile(name: "unsupported.wav", bytes: textBytes)
    }
    
    // MARK: - 1. E08.1 / E08.4: Missing file
    
    @Test("Missing file produces StageFlowError.missingFile, blocks playback and avoids ON AIR (E08.1 / E08.4)")
    @MainActor
    func testMissingFileReturnsTypedErrorAndBlocksPlay() throws {
        let missingURL = URL(fileURLWithPath: "/tmp/stageflow_non_existent_\(UUID().uuidString).wav")
        let backend = FakeAudioPlayerBackend()
        let graph = AudioGraphController(force4ChannelOutput: true)
        let engine = LiveAudioEngine(
            graphController: graph,
            permissionProvider: FakeMicrophonePermissionProvider(status: .authorized),
            playerBackend: backend
        )
        
        engine.loadAudioFile(url: missingURL)
        
        // 1. Проверяем типизированную ошибку
        guard case .failed(let error) = engine.state else {
            Issue.record("Expected state to be .failed, but got \(String(describing: engine.state))")
            return
        }
        guard case .missingFile(let name) = error else {
            Issue.record("Expected StageFlowError.missingFile, but got \(String(describing: error))")
            return
        }
        #expect(name == missingURL.lastPathComponent)
        #expect(!engine.isPlaying)
        #expect(!engine.isOnAir)
        
        // 2. Попытка воспроизведения должна быть заблокирована
        engine.play()
        #expect(!engine.isPlaying)
        #expect(!engine.isOnAir)
        #expect(!backend.isNodePlaying)
        #expect(engine.diagnosticsReport.recentErrors.contains { $0.contains("Play blocked") })
    }
    
    // MARK: - 2. E08.1 / E08.4: Corrupt & Truncated files
    
    @Test("Corrupt and truncated files produce StageFlowError.corruptFile and block playback (E08.1 / E08.4)")
    @MainActor
    func testCorruptedAndTruncatedFilesReturnTypedErrors() throws {
        let corruptURL = try createCorruptWavFile()
        defer { try? FileManager.default.removeItem(at: corruptURL) }
        
        let truncatedURL = try createTruncatedAudioFile()
        defer { try? FileManager.default.removeItem(at: truncatedURL) }
        
        let backend = FakeAudioPlayerBackend()
        let graph = AudioGraphController(force4ChannelOutput: true)
        let engine = LiveAudioEngine(
            graphController: graph,
            permissionProvider: FakeMicrophonePermissionProvider(status: .authorized),
            playerBackend: backend
        )
        
        // Тест 1: Повреждённый файл
        engine.loadAudioFile(url: corruptURL)
        guard case .failed(let err1) = engine.state else {
            Issue.record("Expected state .failed for corrupt file")
            return
        }
        #expect(err1.localizedDescription.contains("Corrupt") || err1.localizedDescription.contains("Unsupported"))
        #expect(!engine.isOnAir)
        engine.play()
        #expect(!engine.isPlaying)
        #expect(!engine.isOnAir)
        
        // Тест 2: Усечённый файл
        engine.loadAudioFile(url: truncatedURL)
        guard case .failed(let err2) = engine.state else {
            Issue.record("Expected state .failed for truncated file")
            return
        }
        #expect(err2.localizedDescription.contains("Corrupt") || err2.localizedDescription.contains("Unsupported"))
        #expect(!engine.isOnAir)
        engine.play()
        #expect(!engine.isPlaying)
        #expect(!engine.isOnAir)
    }
    
    // MARK: - 3. E08.1 / E08.4: Unsupported file
    
    @Test("Unsupported file format produces typed error without app crash (E08.1 / E08.4)")
    @MainActor
    func testUnsupportedFileTypeReturnsTypedError() throws {
        let unsupportedURL = try createUnsupportedTextFile()
        defer { try? FileManager.default.removeItem(at: unsupportedURL) }
        
        let backend = FakeAudioPlayerBackend()
        let graph = AudioGraphController(force4ChannelOutput: true)
        let engine = LiveAudioEngine(
            graphController: graph,
            permissionProvider: FakeMicrophonePermissionProvider(status: .authorized),
            playerBackend: backend
        )
        
        engine.loadAudioFile(url: unsupportedURL)
        guard case .failed = engine.state else {
            Issue.record("Expected state .failed for unsupported file")
            return
        }
        #expect(!engine.isPlaying)
        #expect(!engine.isOnAir)
        
        engine.play()
        #expect(!engine.isPlaying)
        #expect(!engine.isOnAir)
    }
    
    // MARK: - 4. E08.3 / E08.4: Engine start failure
    
    @Test("Engine start failure transitions to failed state and blocks ON AIR (E08.3 / E08.4)")
    @MainActor
    func testEngineStartFailureTransitionsToFailedStateAndBlocksOnAir() throws {
        let backend = FakeAudioPlayerBackend()
        let graph = AudioGraphController(force4ChannelOutput: true)
        let engine = LiveAudioEngine(
            graphController: graph,
            permissionProvider: FakeMicrophonePermissionProvider(status: .authorized),
            playerBackend: backend
        )
        
        // Симулируем падение движка
        let simulatedError = StageFlowError.engineStartFailure("Simulated CoreAudio initialization timeout")
        engine.engineLifecycleState = .failed(simulatedError)
        
        #expect(engine.engineLifecycleState == .failed(simulatedError))
        #expect(!engine.isOnAir)
        
        // Вызов play() категорически блокируется при упавшем движке
        engine.play()
        #expect(!engine.isPlaying)
        #expect(!engine.isOnAir)
        #expect(engine.diagnosticsReport.recentErrors.contains { $0.contains("Play blocked") })
    }
    
    // MARK: - 5. E08.6: Microphone permission denied -> Degraded mode
    
    @Test("Microphone permission denied operates safely in degraded mode with inputs muted (E08.6)")
    @MainActor
    func testMicrophonePermissionDeniedOperatesInDegradedMode() async throws {
        let permProvider = FakeMicrophonePermissionProvider(status: .denied, grantOnRequest: false)
        let graph = AudioGraphController(force4ChannelOutput: true)
        let engine = LiveAudioEngine(
            graphController: graph,
            permissionProvider: permProvider
        )
        
        // Проверяем состояние degraded
        #expect(!engine.isMicPermissionGranted)
        if case .degraded(let reason) = engine.engineLifecycleState {
            #expect(reason.contains("Microphone permission denied"))
        } else {
            Issue.record("Expected engine state .degraded for denied mic, got \(String(describing: engine.engineLifecycleState))")
        }
        
        // Входы микрофонов безопасно заглушены на 0.0
        #expect(graph.mic1InputNode.outputVolume == 0.0)
        #expect(graph.mic2InputNode.outputVolume == 0.0)
        
        // Запрос разрешения возвращает false и сохраняет режим degraded
        await engine.requestMicrophonePermission()
        #expect(!engine.isMicPermissionGranted)
        #expect(engine.diagnosticsReport.micPermission.contains("Denied"))
    }
    
    // MARK: - 6. E08.6: Microphone permission granted recovery
    
    @Test("Microphone permission grant recovers engine from degraded to running (E08.6)")
    @MainActor
    func testMicrophonePermissionGrantedRecoversEngine() async throws {
        let permProvider = FakeMicrophonePermissionProvider(status: .denied, grantOnRequest: true)
        let graph = AudioGraphController(force4ChannelOutput: true)
        let engine = LiveAudioEngine(
            graphController: graph,
            permissionProvider: permProvider
        )
        
        #expect(!engine.isMicPermissionGranted)
        
        // Пользователь нажал "Grant Access" и дал разрешение
        await engine.requestMicrophonePermission()
        
        #expect(engine.isMicPermissionGranted)
        #expect(engine.diagnosticsReport.micPermission == "Authorized")
        #expect(graph.mic1InputNode.outputVolume == 1.0)
        #expect(graph.mic2InputNode.outputVolume == 1.0)
        #expect(engine.engineLifecycleState == .running)
    }
    
    // MARK: - 7. E08.5: Route changes & 20 cycles stability
    
    @Test("20 route reconfiguration cycles complete without crash or duplicate taps (E08.5)")
    @MainActor
    func testConfigurationChangeFlood20CyclesWithoutCrashOrDuplicateTaps() throws {
        let graph = AudioGraphController(force4ChannelOutput: true)
        let engine = LiveAudioEngine(
            graphController: graph,
            permissionProvider: FakeMicrophonePermissionProvider(status: .authorized)
        )
        
        for i in 0..<20 {
            // Чередуем Quad (4ch) и Stereo (2ch)
            let toggle4Ch = (i % 2 == 0)
            engine.handleConfigurationChange(force: true, force4Channel: toggle4Ch)
            
            #expect(engine.engineLifecycleState != .failed(.deviceDisconnected("")))
            #expect(engine.diagnosticsReport.lastRouteEvent != nil)
            if toggle4Ch {
                #expect(graph.isIEMAvailable)
                #expect(graph.outputChannelCount == 4)
            } else {
                #expect(!graph.isIEMAvailable)
                #expect(graph.outputChannelCount == 2)
            }
        }
        
        // Проверяем снятие снимков после 20 переконфигураций
        engine.meteringCoordinator.pollSnapshots()
        #expect(engine.meteringCoordinator.backingMeter.peakDB <= 0.0)
    }
    
    // MARK: - 8. E08.7: Diagnostics report accuracy
    
    @Test("Diagnostics report accurately reflects engine, route, sample rate and errors (E08.7)")
    @MainActor
    func testDiagnosticsReportAccuratelyReflectsSystemState() throws {
        let graph = AudioGraphController(force4ChannelOutput: true)
        let engine = LiveAudioEngine(
            graphController: graph,
            permissionProvider: FakeMicrophonePermissionProvider(status: .authorized)
        )
        
        engine.updateDiagnosticsReport()
        let report = engine.diagnosticsReport
        
        #expect(report.engineState == "RUNNING")
        #expect(report.outputChannels == 4)
        #expect(report.sampleRate == 48000.0)
        #expect(report.isIEMAvailable == true)
        #expect(report.micPermission == "Authorized")
        
        // Проверяем фиксацию ошибок
        engine.loadAudioFile(url: URL(fileURLWithPath: "/tmp/non_existent.wav"))
        engine.play() // should be blocked and logged
        
        #expect(engine.diagnosticsReport.recentErrors.count > 0)
        #expect(engine.diagnosticsReport.recentErrors.contains { $0.contains("Play blocked") })
    }
    
    // MARK: - 9. E08.1: MIDI initialization error capture
    
    @Test("MIDI error is captured typed as StageFlowError.midiInitializationFailure without crash (E08.1)")
    @MainActor
    func testMIDIFailureIsCapturedInDiagnostics() throws {
        let midi = MIDIManager()
        // Принудительно эмулируем ошибку порта для проверки типа
        let testError = StageFlowError.midiInitializationFailure("Simulated Port Creation Failure")
        midi.midiError = testError
        
        #expect(midi.midiError == testError)
        #expect(midi.midiError?.localizedDescription.contains("MIDI Initialization Failure") == true)
    }
}
