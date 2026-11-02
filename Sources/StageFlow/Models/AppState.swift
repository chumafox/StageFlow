import Foundation
import SwiftUI

@MainActor
public class AppState: ObservableObject {
    @Published public var playlist: [SongTrack] = [
        SongTrack(
            title: "StageFlow Demo Song",
            artist: "Apple Silicon Live",
            duration: 20.0,
            lyrics: LyricsParser.generateDefaultPlaceholder()
        )
    ]
    @Published public var selectedTrackID: UUID? = nil
    @Published public var selectedTab: Int = 0 // 0: Mixer, 1: Playlist
    
    // Prompter settings
    @Published public var prompterFontSize: CGFloat = 28.0
    @Published public var autoScrollEnabled: Bool = true
    
    public var selectedTrack: SongTrack? {
        guard let id = selectedTrackID else { return nil }
        return playlist.first { $0.id == id }
    }
    
    public init() {
        self.selectedTrackID = self.playlist.first?.id
    }
    
    public func selectTrack(id: UUID?) {
        self.selectedTrackID = id
    }
    
    public func selectTrack(_ track: SongTrack) {
        self.selectedTrackID = track.id
    }
}
