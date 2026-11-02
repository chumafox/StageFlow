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
    @Published public var lastScrolledLineID: UUID? = nil
    
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
    
    /// Выбирает следующий трек в плейлисте (E09.8).
    public func selectNextTrack() {
        guard let currentID = selectedTrackID,
              let currentIndex = playlist.firstIndex(where: { $0.id == currentID }),
              currentIndex + 1 < playlist.count else { return }
        selectedTrackID = playlist[currentIndex + 1].id
    }
    
    /// Выбирает предыдущий трек в плейлисте (E09.8).
    public func selectPreviousTrack() {
        guard let currentID = selectedTrackID,
              let currentIndex = playlist.firstIndex(where: { $0.id == currentID }),
              currentIndex > 0 else { return }
        selectedTrackID = playlist[currentIndex - 1].id
    }
}
