import Foundation

public struct ChordMarker: Identifiable, Sendable {
    public let id = UUID()
    public let chord: String
    public let characterIndex: Int
}

public struct LyricLine: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: TimeInterval? // Seconds from start (nil if not synced)
    public let rawText: String
    public let plainText: String
    public let chords: [ChordMarker]
    
    public init(timestamp: TimeInterval?, rawText: String, plainText: String, chords: [ChordMarker]) {
        self.timestamp = timestamp
        self.rawText = rawText
        self.plainText = plainText
        self.chords = chords
    }
}

public struct SongTrack: Identifiable, Hashable {
    public let id = UUID()
    public var title: String
    public var artist: String
    public var fileURL: URL?
    public var duration: TimeInterval
    public var lyrics: [LyricLine]
    
    public init(title: String, artist: String = "Live", fileURL: URL? = nil, duration: TimeInterval = 0, lyrics: [LyricLine] = []) {
        self.title = title
        self.artist = artist
        self.fileURL = fileURL
        self.duration = duration
        self.lyrics = lyrics
    }
    
    public static func == (lhs: SongTrack, rhs: SongTrack) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
