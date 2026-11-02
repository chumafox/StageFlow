import Testing
import Foundation
@testable import StageFlow

@Suite("E03 State Boundaries and Selection Tests")
struct AppStateTests {

    @Test("Initial state selects first track by ID")
    @MainActor
    func testInitialSelection() {
        let appState = AppState()
        #expect(appState.selectedTrackID != nil)
        #expect(appState.selectedTrack != nil)
        #expect(appState.selectedTrack?.id == appState.selectedTrackID)
        #expect(appState.selectedTrack?.title == "StageFlow Demo Song")
    }

    @Test("Track selection by ID dynamically computes selectedTrack without diverging copies")
    @MainActor
    func testSelectionByID() {
        let appState = AppState()
        let track2 = SongTrack(title: "Second Song", artist: "Artist 2", duration: 180)
        appState.playlist.append(track2)

        appState.selectTrack(id: track2.id)
        #expect(appState.selectedTrackID == track2.id)
        #expect(appState.selectedTrack?.title == "Second Song")

        // Изменение трека в плейлисте отражается в selectedTrack (Single Source of Truth)
        if let index = appState.playlist.firstIndex(where: { $0.id == track2.id }) {
            appState.playlist[index].title = "Updated Song Title"
        }
        #expect(appState.selectedTrack?.title == "Updated Song Title")
    }

    @Test("Empty playlist produces nil selectedTrack and nil selectedTrackID")
    @MainActor
    func testEmptyPlaylist() {
        let appState = AppState()
        appState.playlist.removeAll()
        appState.selectTrack(id: nil)

        #expect(appState.selectedTrackID == nil)
        #expect(appState.selectedTrack == nil)
    }

    @Test("Pure MIDI decoding is nonisolated and correctly decodes CC and Note events")
    func testMIDIDecoderPureFunction() {
        // UMP packet: CC 7 (Volume), Channel 0, Value 127
        // Word layout: [status_high, channel] [cc] [val] -> 0x00B0077F
        let ccWord: UInt32 = (0xB0 << 16) | (0x07 << 8) | 0x7F
        let ccEvent = MIDIDecoder.decode(word: ccWord)
        #expect(ccEvent == .controlChange(channel: 0, cc: 7, value: 127))

        // UMP packet: Note On (0x90), Note 60, Velocity 100
        let noteWord: UInt32 = (0x90 << 16) | (60 << 8) | 100
        let noteEvent = MIDIDecoder.decode(word: noteWord)
        #expect(noteEvent == .noteOn(channel: 0, note: 60, velocity: 100))

        // Unknown / unhandled message
        let unknownWord: UInt32 = (0xF0 << 16) | (0x00 << 8) | 0x00
        let unknownEvent = MIDIDecoder.decode(word: unknownWord)
        #expect(unknownEvent == .other)
    }
}
