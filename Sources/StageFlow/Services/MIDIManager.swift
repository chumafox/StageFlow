import Foundation
import CoreMIDI

/// Типизированное представление разобранного доменного MIDI-события (E09.1 / E09.2).
public enum MIDIDomainEvent: Sendable, Equatable {
    case controlChange(channel: UInt8, cc: UInt8, value: UInt8)
    case noteOn(channel: UInt8, note: UInt8, velocity: UInt8)
    case noteOff(channel: UInt8, note: UInt8, velocity: UInt8)
    case programChange(channel: UInt8, program: UInt8)
    case pitchBend(channel: UInt8, value: UInt16)
    case other
}

/// Чистый, изолированный декодер Universal MIDI Packet (UMP) и legacy сообщений (E09.1 / E09.2).
public struct MIDIDecoder: Sendable {
    
    /// Декодирует одно 32-битное слово UMP (Universal MIDI Packet) или упакованный legacy статус.
    public static func decode(word: UInt32) -> MIDIDomainEvent {
        let mt = UInt8((word >> 28) & 0x0F)
        
        // 1. Стандартный UMP Message Type 0x2: MIDI 1.0 Channel Voice (32-бит)
        if mt == 0x2 {
            let status = UInt8((word >> 16) & 0xFF)
            let opcode = status & 0xF0
            let channel = status & 0x0F
            let data1 = UInt8((word >> 8) & 0x7F)
            let data2 = UInt8(word & 0x7F)
            return parseChannelVoice(opcode: opcode, channel: channel, data1: data1, data2: data2, rawStatus: status)
        }
        
        // 2. Legacy fallback / Direct packed word: только если MT = 0, но в bits 23..16 статус с установленным старшим битом
        if mt == 0 {
            let status = UInt8((word >> 16) & 0xFF)
            if (status & 0x80) != 0 {
                let opcode = status & 0xF0
                let channel = status & 0x0F
                let data1 = UInt8((word >> 8) & 0x7F)
                let data2 = UInt8(word & 0x7F)
                return parseChannelVoice(opcode: opcode, channel: channel, data1: data1, data2: data2, rawStatus: status)
            }
        }
        
        return .other
    }
    
    private static func parseChannelVoice(opcode: UInt8, channel: UInt8, data1: UInt8, data2: UInt8, rawStatus: UInt8) -> MIDIDomainEvent {
        switch opcode {
        case 0xB0:
            return .controlChange(channel: channel, cc: data1, value: data2)
            
        case 0x90:
            // E09.2: Note On с velocity == 0 строго трактуется как Note Off
            if data2 > 0 {
                return .noteOn(channel: channel, note: data1, velocity: data2)
            } else {
                return .noteOff(channel: channel, note: data1, velocity: 0)
            }
            
        case 0x80:
            return .noteOff(channel: channel, note: data1, velocity: data2)
            
        case 0xC0:
            return .programChange(channel: channel, program: data1)
            
        case 0xE0:
            let bend = UInt16(data1) | (UInt16(data2) << 7)
            return .pitchBend(channel: channel, value: bend)
            
        default:
            return .other
        }
    }
    
    /// Декодирует последовательность слов UMP из пакета, обходя все сообщения (E09.1).
    public static func decode(words: [UInt32]) -> [MIDIDomainEvent] {
        var events: [MIDIDomainEvent] = []
        var idx = 0
        while idx < words.count {
            let word = words[idx]
            let mt = UInt8((word >> 28) & 0x0F)
            
            // Определяем длину UMP сообщения в словах по стандарту MIDI 2.0 / UMP
            let wordLength: Int
            switch mt {
            case 0x0, 0x1, 0x2: wordLength = 1
            case 0x3, 0x4:      wordLength = 2
            case 0x5:           wordLength = 4
            default:            wordLength = 1
            }
            
            let event = decode(word: word)
            events.append(event)
            idx += max(1, wordLength)
        }
        return events
    }
    
    /// Декодирует полный `MIDIEventPacket`, обрабатывая все `wordCount` слов (E09.1).
    public static func decode(packet: UnsafePointer<MIDIEventPacket>) -> [MIDIDomainEvent] {
        let count = Int(packet.pointee.wordCount)
        guard count > 0 else { return [] }
        
        return withUnsafePointer(to: packet.pointee.words) { tuplePtr in
            let rawPtr = UnsafeRawPointer(tuplePtr).assumingMemoryBound(to: UInt32.self)
            let buffer = UnsafeBufferPointer(start: rawPtr, count: count)
            return decode(words: Array(buffer))
        }
    }
    
    /// Декодирует весь `MIDIEventList` со всеми пакетами (E09.1).
    public static func decode(eventList: UnsafePointer<MIDIEventList>) -> [MIDIDomainEvent] {
        var events: [MIDIDomainEvent] = []
        let numPackets = Int(eventList.pointee.numPackets)
        guard numPackets > 0 else { return [] }
        
        withUnsafePointer(to: eventList.pointee.packet) { firstPacketPtr in
            var currentPtr: UnsafePointer<MIDIEventPacket>? = firstPacketPtr
            for _ in 0..<numPackets {
                guard let ptr = currentPtr else { break }
                events.append(contentsOf: decode(packet: ptr))
                currentPtr = UnsafePointer(MIDIEventPacketNext(ptr))
            }
        }
        return events
    }
}

/// Менеджер CoreMIDI устройств, обучения и маршрутизации входящих событий (E09).
@MainActor
public class MIDIManager: ObservableObject {
    public static let shared = MIDIManager()
    
    private var midiClient = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    
    @Published public var connectedDeviceName: String = "No MIDI Devices"
    @Published public var connectedDevices: [String] = []
    @Published public var lastReceivedCC: (channel: UInt8, cc: UInt8, value: UInt8)? = nil
    @Published public var lastLearnedMapping: MIDIMapping? = nil
    @Published public var isLearning: Bool = false
    @Published public var learningTarget: MIDITarget? = nil
    @Published public var midiError: StageFlowError? = nil
    
    public let mappingStore: MIDIMappingStore
    
    // Callbacks для аудио-движка и транспорта
    public var onVolumeChange: ((String, Float) -> Void)?
    public var onPlayPauseTrigger: (() -> Void)?
    public var onStopTrigger: (() -> Void)?
    public var onNextTrackTrigger: (() -> Void)?
    public var onPreviousTrackTrigger: (() -> Void)?
    
    // Отслеживание состояния педали сустейна для исключения повторных триггеров (E09.5)
    private var sustainPedalEngaged: Bool = false
    
    // Coalescing UI обновлений для защиты очереди главного потока (E09.11)
    private var lastUIUpdateTime: TimeInterval = 0
    private let uiUpdateInterval: TimeInterval = 0.033 // ~30 Hz
    private var pendingLastCC: (channel: UInt8, cc: UInt8, value: UInt8)? = nil
    private var pendingUITask: Task<Void, Never>? = nil
    
    public init(mappingStore: MIDIMappingStore? = nil) {
        self.mappingStore = mappingStore ?? .shared
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
            let events = MIDIDecoder.decode(eventList: eventList)
            guard !events.isEmpty else { return }
            
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                for event in events {
                    self.processIncomingEvent(event)
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
    
    // MARK: - Hot-Plug Notification (E09.9 / E09.10)
    
    public func handleMIDINotification(_ notification: UnsafePointer<MIDINotification>) {
        switch notification.pointee.messageID {
        case .msgSetupChanged, .msgObjectAdded, .msgObjectRemoved, .msgPropertyChanged:
            connectAllSources()
        default:
            break
        }
    }
    
    public func connectAllSources() {
        let sourceCount = MIDIGetNumberOfSources()
        var names: [String] = []
        
        for i in 0..<sourceCount {
            let src = MIDIGetSource(i)
            var nameRef: Unmanaged<CFString>?
            let propStatus = MIDIObjectGetStringProperty(src, kMIDIPropertyName, &nameRef)
            let devName: String
            if propStatus == noErr, let n = nameRef?.takeRetainedValue() as String? {
                devName = n
            } else {
                devName = "MIDI Source \(i + 1)"
            }
            names.append(devName)
            
            let connStatus = MIDIPortConnectSource(inputPort, src, nil)
            if connStatus != noErr {
                self.midiError = .midiInitializationFailure("MIDIPortConnectSource failed with OSStatus \(connStatus)")
            }
        }
        
        self.connectedDevices = names
        if names.isEmpty {
            self.connectedDeviceName = "No MIDI Devices"
        } else {
            self.connectedDeviceName = names.joined(separator: ", ")
        }
    }
    
    /// Симуляция смены подключенных устройств для детерминированного тестирования hot-plug (E09.9).
    public func simulateHotPlug(deviceNames: [String]) {
        self.connectedDevices = deviceNames
        self.connectedDeviceName = deviceNames.isEmpty ? "No MIDI Devices" : deviceNames.joined(separator: ", ")
    }
    
    // MARK: - Learning Mode (E09.6)
    
    public func startLearning(target: MIDITarget) {
        self.isLearning = true
        self.learningTarget = target
    }
    
    public func cancelLearning() {
        self.isLearning = false
        self.learningTarget = nil
    }
    
    // MARK: - Event Dispatching & Processing (E09.3 / E09.4 / E09.5 / E09.7 / E09.8 / E09.11)
    
    public func processIncomingEvent(_ event: MIDIDomainEvent) {
        switch event {
        case .controlChange(let channel, let cc, let value):
            updateLastReceivedCC(channel: channel, cc: cc, value: value)
            let normalized = Float(value) / 127.0
            
            // Режим обучения (Learning): сохраняем маппинг в персистентное хранилище
            if isLearning, let target = learningTarget {
                let mapping = MIDIMapping(
                    name: "\(target.displayName) (CC #\(cc))",
                    trigger: .controlChange(channel: channel, cc: cc),
                    target: target
                )
                mappingStore.addOrUpdateMapping(mapping)
                self.lastLearnedMapping = mapping
                self.isLearning = false
                self.learningTarget = nil
                handleTargetAction(target, event: event, normalizedValue: normalized)
                return
            }
            
            // Диспетчеризация через MappingStore с учётом приоритета (E09.7)
            if let target = mappingStore.lookup(event: event) {
                handleTargetAction(target, event: event, normalizedValue: normalized)
            }
            
        case .noteOn(let channel, let note, let velocity):
            guard velocity > 0 else { return }
            
            if isLearning, let target = learningTarget {
                let mapping = MIDIMapping(
                    name: "\(target.displayName) (Note \(note))",
                    trigger: .note(channel: channel, note: note),
                    target: target
                )
                mappingStore.addOrUpdateMapping(mapping)
                self.lastLearnedMapping = mapping
                self.isLearning = false
                self.learningTarget = nil
                handleTargetAction(target, event: event, normalizedValue: 1.0)
                return
            }
            
            // E09.4: Только явно назначенная нота вызывает действие!
            if let target = mappingStore.lookup(event: event) {
                handleTargetAction(target, event: event, normalizedValue: Float(velocity) / 127.0)
            }
            
        case .noteOff:
            break
            
        default:
            break
        }
    }
    
    private func handleTargetAction(_ target: MIDITarget, event: MIDIDomainEvent, normalizedValue: Float) {
        switch target {
        case .masterFOH:
            onVolumeChange?("masterFOH", normalizedValue)
        case .masterIEM:
            onVolumeChange?("masterIEM", normalizedValue)
        case .backingVolume:
            onVolumeChange?("backing", normalizedValue)
        case .mic1Volume:
            onVolumeChange?("mic1", normalizedValue)
        case .mic2Volume:
            onVolumeChange?("mic2", normalizedValue)
        case .reverb:
            onVolumeChange?("reverb", normalizedValue)
            
        case .playPause:
            switch event {
            case .controlChange(_, _, let val):
                // E09.5: Стандартная граница value >= 64 и срабатывание строго на переходе через порог
                let isDown = val >= 64
                if isDown && !sustainPedalEngaged {
                    sustainPedalEngaged = true
                    onPlayPauseTrigger?()
                } else if !isDown && sustainPedalEngaged {
                    sustainPedalEngaged = false
                }
            case .noteOn:
                onPlayPauseTrigger?()
            default:
                break
            }
            
        case .stop:
            onStopTrigger?()
            
        case .nextTrack:
            onNextTrackTrigger?()
            
        case .previousTrack:
            onPreviousTrackTrigger?()
        }
    }
    
    // MARK: - UI Queue Throttling / Coalescing (E09.11)
    
    private func updateLastReceivedCC(channel: UInt8, cc: UInt8, value: UInt8) {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastUIUpdateTime >= uiUpdateInterval {
            lastUIUpdateTime = now
            self.lastReceivedCC = (channel, cc, value)
            self.pendingLastCC = nil
        } else {
            pendingLastCC = (channel, cc, value)
            if pendingUITask == nil {
                pendingUITask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 20_000_000)
                    guard let self = self else { return }
                    if let pending = self.pendingLastCC {
                        self.lastReceivedCC = pending
                        self.pendingLastCC = nil
                    }
                    self.pendingUITask = nil
                }
            }
        }
    }
    
    /// Принудительно сбрасывает накопленное отложенное значение UI (E09.11).
    public func flushUIUpdates() {
        if let pending = pendingLastCC {
            self.lastReceivedCC = pending
            self.pendingLastCC = nil
            self.pendingUITask?.cancel()
            self.pendingUITask = nil
        }
    }
}
