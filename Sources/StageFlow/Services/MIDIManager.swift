import Foundation
import CoreMIDI

public struct MIDIMapping: Identifiable, Codable {
    public var id = UUID()
    public var name: String
    public var channel: UInt8
    public var ccNumber: UInt8
    public var targetKey: String
}

public class MIDIManager: ObservableObject {
    public static let shared = MIDIManager()
    
    private var midiClient = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    
    @Published public var connectedDeviceName: String = "No MIDI Devices"
    @Published public var lastReceivedCC: (channel: UInt8, cc: UInt8, value: UInt8)? = nil
    @Published public var isLearning: Bool = false
    public var learningTarget: String? = nil
    
    // Callback closures for audio engine actions
    public var onVolumeChange: ((String, Float) -> Void)?
    public var onPlayPauseTrigger: (() -> Void)?
    public var onNextTrackTrigger: (() -> Void)?
    
    public init() {
        setupMIDI()
    }
    
    private func setupMIDI() {
        var status = MIDIClientCreateWithBlock("StageFlowMIDIClient" as CFString, &midiClient) { notification in
            // Handle device connect/disconnect
        }
        guard status == noErr else { return }
        
        status = MIDIInputPortCreateWithProtocol(
            midiClient,
            "StageFlowInputPort" as CFString,
            ._1_0,
            &inputPort
        ) { [weak self] eventList, srcConnRefCon in
            self?.handleMIDIEventList(eventList)
        }
        
        connectAllSources()
    }
    
    private func connectAllSources() {
        let sourceCount = MIDIGetNumberOfSources()
        if sourceCount > 0 {
            let src = MIDIGetSource(0)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(src, kMIDIPropertyName, &name)
            if let n = name?.takeRetainedValue() as String? {
                DispatchQueue.main.async {
                    self.connectedDeviceName = n
                }
            }
        }
        for i in 0..<sourceCount {
            let src = MIDIGetSource(i)
            MIDIPortConnectSource(inputPort, src, nil)
        }
    }
    
    private func handleMIDIEventList(_ eventList: UnsafePointer<MIDIEventList>) {
        var packet = eventList.pointee.packet
        for _ in 0..<eventList.pointee.numPackets {
            let wordCount = Int(packet.wordCount)
            if wordCount > 0 {
                let word = packet.words.0
                let status = UInt8((word >> 16) & 0xFF)
                let data1 = UInt8((word >> 8) & 0xFF)
                let data2 = UInt8(word & 0xFF)
                
                let messageType = status & 0xF0
                let channel = status & 0x0F
                
                // Control Change (0xB0)
                if messageType == 0xB0 {
                    DispatchQueue.main.async {
                        self.processCC(channel: channel, cc: data1, value: data2)
                    }
                }
                // Note On (0x90)
                else if messageType == 0x90 && data2 > 0 {
                    DispatchQueue.main.async {
                        // MIDI note pedal: e.g. Note 60 = Play/Pause
                        self.onPlayPauseTrigger?()
                    }
                }
            }
            packet = MIDIEventPacketNext(&packet).pointee
        }
    }
    
    private func processCC(channel: UInt8, cc: UInt8, value: UInt8) {
        self.lastReceivedCC = (channel, cc, value)
        let normalized = Float(value) / 127.0
        
        if isLearning, let target = learningTarget {
            // Запоминаем маппинг
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
