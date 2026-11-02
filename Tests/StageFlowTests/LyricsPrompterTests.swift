import Foundation
import Testing
@testable import StageFlow

@Suite("E10 Lyrics, ChordPro & Prompter Tests")
struct LyricsPrompterTests {
    
    // MARK: - E10.1 & E10.2: Fractional Seconds Precision
    
    @Test("LRC fractional seconds calculate accurately for 1, 2, and 3 digits (E10.1 / E10.2 / SF-08.1)")
    func testFractionalSecondsCalculations() {
        // 1 digit fraction: [01:02.5] MUST equal 62.5s (in old code it was 62.05s)
        let doc1 = LyricsParser.parseDocument("[01:02.5]One digit fraction")
        #expect(doc1.lines.count == 1)
        #expect(abs((doc1.lines[0].timestamp ?? 0) - 62.5) < 0.001)
        
        // 2 digits fraction: [00:10.25] = 10.25s
        let doc2 = LyricsParser.parseDocument("[00:10.25]Two digits fraction")
        #expect(abs((doc2.lines[0].timestamp ?? 0) - 10.25) < 0.001)
        
        // 3 digits fraction: [00:15.123] = 15.123s
        let doc3 = LyricsParser.parseDocument("[00:15.123]Three digits fraction")
        #expect(abs((doc3.lines[0].timestamp ?? 0) - 15.123) < 0.001)
        
        // Colon fraction separator: [02:30:50] = 150.50s
        let doc4 = LyricsParser.parseDocument("[02:30:50]Colon fraction separator")
        #expect(abs((doc4.lines[0].timestamp ?? 0) - 150.5) < 0.001)
    }
    
    // MARK: - E10.3 & E10.4: Multiple Timestamps & LRC Metadata Tags
    
    @Test("Multiple timestamps per line expand into separate chronological occurrences (E10.4)")
    func testMultipleTimestampsPerLine() {
        let lrc = """
        [00:10.00][00:25.50][01:00.00] Chorus: [Am]I love this [F]song
        [00:05.00] Intro verse
        """
        let doc = LyricsParser.parseDocument(lrc)
        
        // Total lines should be 4 (1 from intro + 3 from chorus)
        #expect(doc.lines.count == 4)
        
        // Must be sorted chronologically: 5.0, 10.0, 25.5, 60.0
        #expect(abs((doc.lines[0].timestamp ?? 0) - 5.0) < 0.001)
        #expect(doc.lines[0].plainText == "Intro verse")
        
        #expect(abs((doc.lines[1].timestamp ?? 0) - 10.0) < 0.001)
        #expect(doc.lines[1].plainText == "Chorus: I love this song")
        #expect(doc.lines[1].chords.count == 2)
        
        #expect(abs((doc.lines[2].timestamp ?? 0) - 25.5) < 0.001)
        #expect(doc.lines[2].plainText == "Chorus: I love this song")
        
        #expect(abs((doc.lines[3].timestamp ?? 0) - 60.0) < 0.001)
        #expect(doc.lines[3].plainText == "Chorus: I love this song")
    }
    
    @Test("LRC header metadata tags are captured and not parsed as false chords (E10.3 / SF-08.3)")
    func testLRCMetadataTags() {
        let lrc = """
        [ti: Bohemian Rhapsody]
        [ar: Queen]
        [al: A Night at the Opera]
        [offset: +500]
        [00:02.00] Is this the real life?
        """
        let doc = LyricsParser.parseDocument(lrc)
        
        #expect(doc.title == "Bohemian Rhapsody")
        #expect(doc.artist == "Queen")
        #expect(abs(doc.offset - 0.5) < 0.001)
        
        // Line timestamp 2.0s + offset 0.5s = 2.5s
        #expect(doc.lines.count == 1)
        #expect(abs((doc.lines[0].timestamp ?? 0) - 2.5) < 0.001)
        #expect(doc.lines[0].plainText == "Is this the real life?")
        // Metadata tags must not be parsed as chords!
        #expect(doc.lines[0].chords.isEmpty)
    }
    
    // MARK: - E10.5: ChordPro Directives & Cyrillic / Unicode Chords
    
    @Test("ChordPro directives, Cyrillic lyrics, and inline chords parse accurately (E10.5)")
    func testChordProDirectivesAndCyrillic() {
        let chordPro = """
        {title: Звезда по имени Солнце}
        {artist: Кино}
        {bpm: 120}
        {key: Dm}
        {capo: 2}
        {c: Куплет 1}
        [Dm]Белый снег, [Am]серый лёд
        [C]На растрескавшейся [G]земле
        """
        let doc = LyricsParser.parseDocument(chordPro)
        
        #expect(doc.title == "Звезда по имени Солнце")
        #expect(doc.artist == "Кино")
        #expect(doc.bpm == 120)
        #expect(doc.key == "Dm")
        #expect(doc.capo == 2)
        
        // Should have section comment line + 2 song lines
        #expect(doc.lines.count == 3)
        #expect(doc.lines[0].plainText == "--- КУПЛЕТ 1 ---")
        
        let line1 = doc.lines[1]
        #expect(line1.plainText == "Белый снег, серый лёд")
        #expect(line1.chords.count == 2)
        #expect(line1.chords[0].chord == "Dm")
        #expect(line1.chords[0].characterIndex == 0)
        #expect(line1.chords[1].chord == "Am")
        #expect(line1.chords[1].characterIndex == 12)
        
        let line2 = doc.lines[2]
        #expect(line2.plainText == "На растрескавшейся земле")
        #expect(line2.chords.count == 2)
        #expect(line2.chords[0].chord == "C")
        #expect(line2.chords[0].characterIndex == 0)
        #expect(line2.chords[1].chord == "G")
        #expect(line2.chords[1].characterIndex == 19)
    }
    
    // MARK: - E10.8: Segment Layout & Visual Chord Alignment
    
    @Test("LyricLine segments accurately split text under corresponding chords (E10.8)")
    func testLyricLineSegments() {
        let line = LyricLine(
            timestamp: 10.0,
            rawText: "[Am]Welcome to [F]StageFlow on macOS",
            plainText: "Welcome to StageFlow on macOS",
            chords: [
                ChordMarker(chord: "Am", characterIndex: 0),
                ChordMarker(chord: "F", characterIndex: 11)
            ]
        )
        
        let segments = line.segments
        #expect(segments.count == 2)
        
        #expect(segments[0].chord == "Am")
        #expect(segments[0].text == "Welcome to ")
        
        #expect(segments[1].chord == "F")
        #expect(segments[1].text == "StageFlow on macOS")
    }
    
    @Test("Leading text before first chord creates leading segment without chord (E10.8)")
    func testLeadingTextSegment() {
        let line = LyricLine(
            timestamp: 5.0,
            rawText: "Intro: [C]start [G]now",
            plainText: "Intro: start now",
            chords: [
                ChordMarker(chord: "C", characterIndex: 7),
                ChordMarker(chord: "G", characterIndex: 13)
            ]
        )
        let segments = line.segments
        #expect(segments.count == 3)
        #expect(segments[0].chord == nil)
        #expect(segments[0].text == "Intro: ")
        #expect(segments[1].chord == "C")
        #expect(segments[1].text == "start ")
        #expect(segments[2].chord == "G")
        #expect(segments[2].text == "now")
    }
    
    // MARK: - E10.7: Active Line Algorithm
    
    @Test("Active line dynamic algorithm eliminates hardcoded 3.8s limit (E10.7 / SF-08)")
    func testActiveLineAlgorithm() {
        let line1 = LyricLine(timestamp: 5.0, rawText: "L1", plainText: "Line 1", chords: [])
        let line2 = LyricLine(timestamp: 7.0, rawText: "L2", plainText: "Line 2 (short 2s)", chords: [])
        let line3 = LyricLine(timestamp: 30.0, rawText: "L3", plainText: "Line 3 (long 23s gap)", chords: [])
        let lines = [line1, line2, line3]
        
        // 1. Before first timestamp (0.0s..4.9s) -> nil (Intro)
        #expect(LyricLine.activeLineID(in: lines, at: 0.0) == nil)
        #expect(LyricLine.activeLineID(in: lines, at: 4.9) == nil)
        
        // 2. Line 1 is active from 5.0s up to 6.999s
        #expect(LyricLine.activeLineID(in: lines, at: 5.0) == line1.id)
        #expect(LyricLine.activeLineID(in: lines, at: 6.9) == line1.id)
        
        // 3. Line 2 takes over at 7.0s and stays active until 29.999s (NO 3.8s expiration!)
        #expect(LyricLine.activeLineID(in: lines, at: 7.0) == line2.id)
        #expect(LyricLine.activeLineID(in: lines, at: 15.0) == line2.id, "Line 2 must remain active after 3.8s!")
        #expect(LyricLine.activeLineID(in: lines, at: 29.9) == line2.id)
        
        // 4. Line 3 takes over at 30.0s and stays active to end of track
        #expect(LyricLine.activeLineID(in: lines, at: 30.0) == line3.id)
        #expect(LyricLine.activeLineID(in: lines, at: 120.0) == line3.id)
    }
    
    // MARK: - E10.10: Empty, Placeholder & Whitespace Handling
    
    @Test("Empty lines and default placeholder behave predictably (E10.10)")
    func testEmptyAndPlaceholder() {
        let emptyDoc = LyricsParser.parseDocument("")
        #expect(emptyDoc.lines.isEmpty)
        
        let placeholder = LyricsParser.generateDefaultPlaceholder()
        #expect(placeholder.count == 5)
        #expect(placeholder[0].plainText.contains("INTRO"))
        
        // Whitespace only
        let wsDoc = LyricsParser.parseDocument("   \n\n   \t  ")
        #expect(wsDoc.lines.isEmpty || wsDoc.lines.allSatisfy { $0.plainText.isEmpty })
    }
}
