import Foundation
import AVFoundation

/// Типизированные ошибки StageFlow согласно E08.1 / SF-05
public enum StageFlowError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedFileType(String)
    case corruptFile(String)
    case missingFile(String)
    case permissionDenied(String)
    case metadataFailure(String)
    case engineStartFailure(String)
    case unavailableRoute(String)
    case midiInitializationFailure(String)
    case deviceDisconnected(String)
    
    public var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let msg):
            return "Unsupported File Type: \(msg)"
        case .corruptFile(let msg):
            return "Corrupted Audio File: \(msg)"
        case .missingFile(let msg):
            return "Missing File: \(msg)"
        case .permissionDenied(let msg):
            return "Permission Denied: \(msg)"
        case .metadataFailure(let msg):
            return "Metadata Read Failure: \(msg)"
        case .engineStartFailure(let msg):
            return "Audio Engine Start Failure: \(msg)"
        case .unavailableRoute(let msg):
            return "Unavailable Audio Route: \(msg)"
        case .midiInitializationFailure(let msg):
            return "MIDI Initialization Failure: \(msg)"
        case .deviceDisconnected(let msg):
            return "Audio Device Disconnected: \(msg)"
        }
    }
}

/// Состояния жизненного цикла аудиодвижка согласно E08.3
public enum EngineLifecycleState: Equatable, Sendable {
    case starting
    case ready
    case running
    case degraded(String)
    case stopped
    case failed(StageFlowError)
    
    public var displayName: String {
        switch self {
        case .starting:
            return "STARTING"
        case .ready:
            return "READY"
        case .running:
            return "RUNNING"
        case .degraded(let reason):
            return "DEGRADED (\(reason))"
        case .stopped:
            return "STOPPED"
        case .failed(let error):
            return "FAILED (\(error.localizedDescription))"
        }
    }
}

/// Статус разрешений на использование микрофона согласно E08.6
public enum MicrophonePermissionStatus: Sendable, Equatable {
    case authorized
    case denied
    case notDetermined
}

/// Протокол проверки и запроса доступа к микрофону для изоляции и тестируемости
public protocol MicrophonePermissionProviding: Sendable {
    func checkPermission() -> MicrophonePermissionStatus
    func requestPermission() async -> Bool
}

/// Системная реализация проверки разрешений микрофона
public struct SystemMicrophonePermissionProvider: MicrophonePermissionProviding {
    public init() {}
    
    public func checkPermission() -> MicrophonePermissionStatus {
        #if os(macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
        #else
        return .authorized
        #endif
    }
    
    public func requestPermission() async -> Bool {
        #if os(macOS)
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        #else
        return true
        #endif
    }
}

/// Fake-провайдер разрешений для детерминированного тестирования
public struct FakeMicrophonePermissionProvider: MicrophonePermissionProviding {
    public var status: MicrophonePermissionStatus
    public var grantOnRequest: Bool
    
    public init(status: MicrophonePermissionStatus = .authorized, grantOnRequest: Bool = true) {
        self.status = status
        self.grantOnRequest = grantOnRequest
    }
    
    public func checkPermission() -> MicrophonePermissionStatus {
        return status
    }
    
    public func requestPermission() async -> Bool {
        return grantOnRequest
    }
}

/// Сводка диагностики аудиодвижка для UI и логов согласно E08.7
public struct DiagnosticsReport: Sendable, Equatable {
    public var engineState: String
    public var outputRoute: String
    public var outputChannels: Int
    public var sampleRate: Double
    public var bufferSize: AVAudioFrameCount
    public var isIEMAvailable: Bool
    public var micPermission: String
    public var midiDevice: String
    public var recentErrors: [String]
    public var lastRouteEvent: String?
    
    public init(
        engineState: String = "stopped",
        outputRoute: String = "Default",
        outputChannels: Int = 2,
        sampleRate: Double = 48000.0,
        bufferSize: AVAudioFrameCount = 512,
        isIEMAvailable: Bool = false,
        micPermission: String = "Unknown",
        midiDevice: String = "No MIDI Devices",
        recentErrors: [String] = [],
        lastRouteEvent: String? = nil
    ) {
        self.engineState = engineState
        self.outputRoute = outputRoute
        self.outputChannels = outputChannels
        self.sampleRate = sampleRate
        self.bufferSize = bufferSize
        self.isIEMAvailable = isIEMAvailable
        self.micPermission = micPermission
        self.midiDevice = midiDevice
        self.recentErrors = recentErrors
        self.lastRouteEvent = lastRouteEvent
    }
}
