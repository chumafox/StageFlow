import Foundation
import CoreMIDI

public struct MIDIMapping: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var name: String
    public var channel: UInt8
    public var ccNumber: UInt8
    public var targetKey: String
    
    public init(name: String, channel: UInt8, ccNumber: UInt8, targetKey: String) {
        self.name = name
        self.channel = channel
        self.ccNumber = ccNumber
        self.targetKey = targetKey
    }
}

public enum MIDIDomainEvent: Sendable, Equatable {
    case controlChange(channel: UInt8, cc: UInt8, value: UInt8)
    case noteOn(channel: UInt8, note: UInt8, velocity: UInt8)
    case other
}

public struct MIDIDecoder: Sendable {
    public static func decode(word: UInt32) -> MIDIDomainEvent {
        let status = UInt8((word >> 16) & 0xFF)
        let data1 = UInt8((word >> 8) & 0xFF)
        let data2 = UInt8(word & 0xFF)
        
        let messageType = status & 0xF0
        let channel = status & 0x0F
        
        if messageType == 0xB0 {
            return .controlChange(channel: channel, cc: data1, value: data2)
        } else if messageType == 0x90 && data2 > 0 {
            return .noteOn(channel: channel, note: data1, velocity: data2)
        }
        return .other
    }
}

@MainActor
public class MIDIManager: ObservableObject {
    public static let shared = MIDIManager()
    
    private var midiClient = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    
    @Published public var connectedDeviceName: String = "No MIDI Devices"
    @Published public var lastReceivedCC: (channel: UInt8, cc: UInt8, value: UInt8)? = nil
    @Published public var isLearning: Bool = false
    @Published public var midiError: StageFlowError? = nil
    public var learningTarget: String? = nil
    
    // Callback closures for audio engine actions
    public var onVolumeChange: ((String, Float) -> Void)?
    public var onPlayPauseTrigger: (() -> Void)?
    public var onNextTrackTrigger: (() -> Void)?
    
    public init() {
        setupMIDI()
    }
    
    private func setupMIDI() {
        var status = MIDIClientCreateWithBlock("StageFlowMIDIClient" as CFString, &midiClient) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleMIDINotification(notification)
            }
        }
        guard status == noErr else {
            let err = StageFlowError.midiInitializationFailure("MIDIClientCreate failed with OSStatus \(status)")
            self.midiError = err
            self.connectedDeviceName = "MIDI Init Failed"
            return
        }
        
        status = MIDIInputPortCreateWithProtocol(
            midiClient,
            "StageFlowInputPort" as CFString,
            ._1_0,
            &inputPort
        ) { [weak self] eventList, _ in
            var events: [MIDIDomainEvent] = []
            var packet = eventList.pointee.packet
            for _ in 0..<eventList.pointee.numPackets {
                let wordCount = Int(packet.wordCount)
                if wordCount > 0 {
                    let decoded = MIDIDecoder.decode(word: packet.words.0)
                    if decoded != .other {
                        events.append(decoded)
                    }
                }
                packet = MIDIEventPacketNext(&packet).pointee
            }
            
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                for event in events {
                    self.handleDomainEvent(event)
                }
            }
        }
        
        guard status == noErr else {
            let err = StageFlowError.midiInitializationFailure("MIDIInputPortCreate failed with OSStatus \(status)")
            self.midiError = err
            self.connectedDeviceName = "MIDI Port Failed"
            return
        }
        
        self.midiError = nil
        connectAllSources()
    }
    
    private func handleMIDINotification(_ notification: UnsafePointer<MIDINotification>) {
        switch notification.pointee.messageID {
        case .msgSetupChanged, .msgObjectAdded, .msgObjectRemoved:
            connectAllSources()
        default:
            break
        }
    }
    
    private func connectAllSources() {
        let sourceCount = MIDIGetNumberOfSources()
        if sourceCount > 0 {
            let src = MIDIGetSource(0)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(src, kMIDIPropertyName, &name)
            if let n = name?.takeRetainedValue() as String? {
                self.connectedDeviceName = n
            }
        }
        for i in 0..<sourceCount {
            let src = MIDIGetSource(i)
            MIDIPortConnectSource(inputPort, src, nil)
        }
    }
    
    private func handleDomainEvent(_ event: MIDIDomainEvent) {
        switch event {
        case .controlChange(let channel, let cc, let value):
            processCC(channel: channel, cc: cc, value: value)
        case .noteOn:
            // MIDI note pedal: e.g. Note 60 = Play/Pause
            onPlayPauseTrigger?()
        case .other:
            break
        }
    }
    
    private func processCC(channel: UInt8, cc: UInt8, value: UInt8) {
        self.lastReceivedCC = (channel, cc, value)
        let normalized = Float(value) / 127.0
        
        if isLearning, let target = learningTarget {
            isLearning = false
            learningTarget = nil
            onVolumeChange?(target, normalized)
            return
        }
        
        // Стандартные предустановки
        switch cc {
        case 7: // Master Volume
            onVolumeChange?("masterFOH", normalized)
        case 1: // Mod Wheel -> Reverb
            onVolumeChange?("reverb", normalized)
        case 64: // Sustain pedal -> Play/Pause
            if value > 64 { onPlayPauseTrigger?() }
        default:
            break
        }
    }
}
