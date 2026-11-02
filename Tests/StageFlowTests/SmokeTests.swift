import Testing
@testable import StageFlow

@Suite("StageFlow Smoke Tests")
struct SmokeTests {
    @Test("Basic modules and models load successfully")
    @MainActor
    func moduleLoads() {
        let state = AppState()
        #expect(!state.playlist.isEmpty)
        #expect(state.playlist.first?.title == "StageFlow Demo Song")
        
        let lyrics = LyricsParser.generateDefaultPlaceholder()
        #expect(!lyrics.isEmpty)
        
        let track = SongTrack(title: "Test Track", duration: 120)
        #expect(track.title == "Test Track")
        #expect(track.duration == 120)
    }
}
