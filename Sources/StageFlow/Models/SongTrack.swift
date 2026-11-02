import Foundation

public struct ChordMarker: Identifiable, Sendable, Equatable, Hashable, Codable {
    public let id: UUID
    public let chord: String
    public let characterIndex: Int
    
    public init(id: UUID = UUID(), chord: String, characterIndex: Int) {
        self.id = id
        self.chord = chord
        self.characterIndex = characterIndex
    }
}

public struct LyricSegment: Identifiable, Sendable, Equatable, Hashable, Codable {
    public let id: UUID
    public let chord: String?
    public let text: String
    
    public init(id: UUID = UUID(), chord: String?, text: String) {
        self.id = id
        self.chord = chord
        self.text = text
    }
}

public struct LyricLine: Identifiable, Sendable, Equatable, Hashable, Codable {
    public let id: UUID
    public let timestamp: TimeInterval? // Seconds from start (nil if not synced)
    public let rawText: String
    public let plainText: String
    public let chords: [ChordMarker]
    
    public init(id: UUID = UUID(), timestamp: TimeInterval?, rawText: String, plainText: String, chords: [ChordMarker]) {
        self.id = id
        self.timestamp = timestamp
        self.rawText = rawText
        self.plainText = plainText
        self.chords = chords
    }
    
    /// Сегменты для точного вертикального выравнивания аккордов над слогами (E10.8).
    public var segments: [LyricSegment] {
        if chords.isEmpty {
            return plainText.isEmpty ? [] : [LyricSegment(chord: nil, text: plainText)]
        }
        
        var result: [LyricSegment] = []
        let sortedChords = chords.sorted { $0.characterIndex < $1.characterIndex }
        let chars = Array(plainText)
        var curIdx = 0
        
        for i in 0..<sortedChords.count {
            let cm = sortedChords[i]
            let chordIdx = min(max(0, cm.characterIndex), chars.count)
            
            // Текст до аккорда
            if chordIdx > curIdx {
                let leading = String(chars[curIdx..<chordIdx])
                result.append(LyricSegment(chord: nil, text: leading))
                curIdx = chordIdx
            }
            
            // Текст под текущим аккордом до следующего аккорда или конца строки
            let nextIdx: Int
            if i + 1 < sortedChords.count {
                nextIdx = min(max(chordIdx, sortedChords[i + 1].characterIndex), chars.count)
            } else {
                nextIdx = chars.count
            }
            
            let slice = String(chars[chordIdx..<nextIdx])
            result.append(LyricSegment(chord: cm.chord, text: slice))
            curIdx = nextIdx
        }
        
        if curIdx < chars.count {
            let trailing = String(chars[curIdx...])
            result.append(LyricSegment(chord: nil, text: trailing))
        }
        
        return result
    }
    
    /// Алгоритм определения активной строки (E10.7):
    /// Активна строка с timestamp <= currentTime до timestamp следующей синхронизированной строки.
    public static func activeLineID(in lines: [LyricLine], at currentTime: TimeInterval) -> UUID? {
        let syncedLines = lines.filter { $0.timestamp != nil }
        guard let first = syncedLines.first, let firstTime = first.timestamp, currentTime >= firstTime else {
            return nil
        }
        
        for i in 0..<syncedLines.count {
            let cur = syncedLines[i]
            guard let curTime = cur.timestamp else { continue }
            let nextTime: TimeInterval
            if i + 1 < syncedLines.count, let nxt = syncedLines[i + 1].timestamp {
                nextTime = nxt
            } else {
                nextTime = .infinity
            }
            
            if currentTime >= curTime && currentTime < nextTime {
                return cur.id
            }
        }
        return syncedLines.last?.id
    }
}

public struct SongTrack: Identifiable, Hashable, Equatable, Sendable, Codable {
    public let id: UUID
    public var title: String
    public var artist: String
    public var fileURL: URL?
    public var duration: TimeInterval
    public var lyrics: [LyricLine]
    public var bookmarkData: Data?
    public var isAvailable: Bool
    
    public init(
        id: UUID = UUID(),
        title: String,
        artist: String = "Live",
        fileURL: URL? = nil,
        duration: TimeInterval = 0,
        lyrics: [LyricLine] = [],
        bookmarkData: Data? = nil,
        isAvailable: Bool = true
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.fileURL = fileURL
        self.duration = duration
        self.lyrics = lyrics
        self.bookmarkData = bookmarkData
        self.isAvailable = isAvailable
    }
    
    public static func == (lhs: SongTrack, rhs: SongTrack) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
