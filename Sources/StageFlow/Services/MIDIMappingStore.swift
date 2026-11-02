import Foundation

/// Целевые параметры и команды приложения, доступные для управления по MIDI (E09.3 / E09.8).
public enum MIDITarget: String, Codable, CaseIterable, Sendable {
    case masterFOH = "masterFOH"
    case masterIEM = "masterIEM"
    case backingVolume = "backing"
    case mic1Volume = "mic1"
    case mic2Volume = "mic2"
    case reverb = "reverb"
    case playPause = "playPause"
    case stop = "stop"
    case nextTrack = "nextTrack"
    case previousTrack = "previousTrack"
    
    public var isContinuous: Bool {
        switch self {
        case .masterFOH, .masterIEM, .backingVolume, .mic1Volume, .mic2Volume, .reverb:
            return true
        case .playPause, .stop, .nextTrack, .previousTrack:
            return false
        }
    }
    
    public var displayName: String {
        switch self {
        case .masterFOH: return "FOH Master Volume"
        case .masterIEM: return "IEM Master Volume"
        case .backingVolume: return "Backing Track Volume"
        case .mic1Volume: return "Mic 1 Volume"
        case .mic2Volume: return "Mic 2 Volume"
        case .reverb: return "Reverb Send"
        case .playPause: return "Play / Pause"
        case .stop: return "Stop"
        case .nextTrack: return "Next Track"
        case .previousTrack: return "Previous Track"
        }
    }
}

/// Источник MIDI-триггера: CC или Note (E09.3).
/// Канал 0–15 соответствует UI каналам 1–16. nil означает любой канал (Omni).
public enum MIDITrigger: Codable, Equatable, Hashable, Sendable {
    case controlChange(channel: UInt8?, cc: UInt8)
    case note(channel: UInt8?, note: UInt8)
    
    public var description: String {
        switch self {
        case .controlChange(let ch, let cc):
            let chStr = ch.map { "Ch \($0 + 1)" } ?? "Omni"
            return "\(chStr) | CC #\(cc)"
        case .note(let ch, let note):
            let chStr = ch.map { "Ch \($0 + 1)" } ?? "Omni"
            return "\(chStr) | Note \(note)"
        }
    }
}

/// Назначение MIDI-триггера на целевое действие (E09.3).
public struct MIDIMapping: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var trigger: MIDITrigger
    public var target: MIDITarget
    
    public init(id: UUID = UUID(), name: String, trigger: MIDITrigger, target: MIDITarget) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.target = target
    }
}

/// Хранилище и диспетчер пользовательских и стандартных MIDI-назначений (E09.6 / E09.7).
@MainActor
public class MIDIMappingStore: ObservableObject {
    public static let shared = MIDIMappingStore()
    
    @Published public private(set) var userMappings: [MIDIMapping] = []
    
    private let storageKey: String
    private let userDefaults: UserDefaults
    
    public init(storageKey: String = "StageFlow.MIDIMappings", userDefaults: UserDefaults = .standard) {
        self.storageKey = storageKey
        self.userDefaults = userDefaults
        load()
    }
    
    public func addOrUpdateMapping(_ mapping: MIDIMapping) {
        if let idx = userMappings.firstIndex(where: { $0.trigger == mapping.trigger }) {
            userMappings[idx] = mapping
        } else {
            userMappings.append(mapping)
        }
        save()
    }
    
    public func removeMapping(id: UUID) {
        userMappings.removeAll { $0.id == id }
        save()
    }
    
    public func removeAll() {
        userMappings.removeAll()
        save()
    }
    
    public func save() {
        if let data = try? JSONEncoder().encode(userMappings) {
            userDefaults.set(data, forKey: storageKey)
        }
    }
    
    public func load() {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([MIDIMapping].self, from: data) else {
            return
        }
        self.userMappings = decoded
    }
    
    /// Диспетчеризация входящего события (E09.7 Precedence):
    /// 1. Пользовательские mappings имеют строгий приоритет над defaults.
    /// 2. Сначала проверяется точное совпадение по каналу, затем Omni (channel == nil).
    /// 3. Для неназначенных CC действуют стандартные пресеты (CC 7 -> FOH, CC 1 -> Reverb, CC 64 -> Play/Pause).
    /// 4. Для неназначенных Note On действий НЕТ (E09.4).
    public func lookup(event: MIDIDomainEvent) -> MIDITarget? {
        switch event {
        case .controlChange(let channel, let cc, _):
            // 1. Пользовательский маппинг с точным каналом
            if let m = userMappings.first(where: { $0.trigger == .controlChange(channel: channel, cc: cc) }) {
                return m.target
            }
            // 2. Пользовательский маппинг Omni
            if let m = userMappings.first(where: { $0.trigger == .controlChange(channel: nil, cc: cc) }) {
                return m.target
            }
            // 3. Стандартные заводские пресеты
            switch cc {
            case 7: return .masterFOH
            case 1: return .reverb
            case 64: return .playPause
            default: return nil
            }
            
        case .noteOn(let channel, let note, let velocity):
            guard velocity > 0 else { return nil }
            // 1. Точный канал
            if let m = userMappings.first(where: { $0.trigger == .note(channel: channel, note: note) }) {
                return m.target
            }
            // 2. Omni
            if let m = userMappings.first(where: { $0.trigger == .note(channel: nil, note: note) }) {
                return m.target
            }
            // Неназначенные ноты строго игнорируются (E09.4)
            return nil
            
        default:
            return nil
        }
    }
    
    public func checkConflict(for trigger: MIDITrigger) -> MIDIMapping? {
        userMappings.first(where: { $0.trigger == trigger })
    }
}
