import Foundation
import SwiftUI

public class AppState: ObservableObject {
    @Published public var playlist: [SongTrack] = [
        SongTrack(
            title: "StageFlow Demo Song",
            artist: "Apple Silicon Live",
            duration: 20.0,
            lyrics: LyricsParser.generateDefaultPlaceholder()
        )
    ]
    @Published public var selectedTrack: SongTrack? = nil
    @Published public var selectedTab: Int = 0 // 0: Mixer, 1: Playlist
    
    // Prompter settings
    @Published public var prompterFontSize: CGFloat = 28.0
    @Published public var autoScrollEnabled: Bool = true
    
    public init() {
        self.selectedTrack = self.playlist.first
    }
}
