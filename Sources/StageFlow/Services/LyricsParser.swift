import Foundation
import AVFoundation

public class LyricsParser {
    public static func extractLyrics(from fileURL: URL) -> [LyricLine] {
        let asset = AVURLAsset(url: fileURL)
        var rawText: String? = nil
        
        // 1. Попытка достать USLT или тег lyrics из контейнера
        for item in asset.metadata {
            let keyStr = (item.key as? String)?.lowercased() ?? ""
            if item.commonKey?.rawValue == "lyrics" ||
               item.identifier?.rawValue.contains("USLT") == true ||
               keyStr.contains("lyric") {
                rawText = item.stringValue
                if rawText != nil { break }
            }
        }
        
        // 2. Поиск внешнего синхронизированного .lrc или .txt файла
        if rawText == nil {
            let lrcURL = fileURL.deletingPathExtension().appendingPathExtension("lrc")
            let txtURL = fileURL.deletingPathExtension().appendingPathExtension("txt")
            if let content = try? String(contentsOf: lrcURL, encoding: .utf8) {
                rawText = content
            } else if let content = try? String(contentsOf: txtURL, encoding: .utf8) {
                rawText = content
            }
        }
        
        guard let text = rawText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return generateDefaultPlaceholder()
        }
        
        return parseChordPro(text)
    }
    
    public static func parseChordPro(_ text: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let rawLines = text.components(separatedBy: .newlines)
        
        let timeRegex = try? NSRegularExpression(pattern: #"^\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#)
        let chordRegex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]"#)
        
        for rawLine in rawLines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                // Пустая строка для разделения куплетов
                lines.append(LyricLine(timestamp: nil, rawText: "", plainText: "", chords: []))
                continue
            }
            // Пропуск служебных директив ChordPro вида {title:...}, {artist:...}
            if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
                continue
            }
            
            var lineText = trimmed
            var time: TimeInterval? = nil
            
            // Проверка временных меток вида [01:23.45]
            if let match = timeRegex?.firstMatch(in: lineText, range: NSRange(lineText.startIndex..., in: lineText)) {
                if let minRange = Range(match.range(at: 1), in: lineText),
                   let secRange = Range(match.range(at: 2), in: lineText) {
                    let mins = Double(lineText[minRange]) ?? 0
                    let secs = Double(lineText[secRange]) ?? 0
                    var millis = 0.0
                    if match.numberOfRanges > 3, match.range(at: 3).location != NSNotFound,
                       let msRange = Range(match.range(at: 3), in: lineText) {
                        let msStr = String(lineText[msRange])
                        millis = (Double(msStr) ?? 0) / (msStr.count == 3 ? 1000.0 : 100.0)
                    }
                    time = (mins * 60.0) + secs + millis
                }
                lineText = timeRegex?.stringByReplacingMatches(in: lineText, range: NSRange(lineText.startIndex..., in: lineText), withTemplate: "").trimmingCharacters(in: .whitespaces) ?? lineText
            }
            
            // Парсинг аккордов [Am], [G/B], [Cmaj7]
            var chords: [ChordMarker] = []
            var cleanText = ""
            var lastIndex = lineText.startIndex
            
            if let chordMatches = chordRegex?.matches(in: lineText, range: NSRange(lineText.startIndex..., in: lineText)) {
                for m in chordMatches {
                    if let chordRange = Range(m.range(at: 1), in: lineText),
                       let fullRange = Range(m.range(at: 0), in: lineText) {
                        cleanText += lineText[lastIndex..<fullRange.lowerBound]
                        let chordName = String(lineText[chordRange])
                        chords.append(ChordMarker(chord: chordName, characterIndex: cleanText.count))
                        lastIndex = fullRange.upperBound
                    }
                }
            }
            cleanText += lineText[lastIndex...]
            
            lines.append(LyricLine(timestamp: time, rawText: rawLine, plainText: cleanText, chords: chords))
        }
        
        return lines
    }
    
    public static func generateDefaultPlaceholder() -> [LyricLine] {
        return [
            LyricLine(timestamp: 0.0, rawText: "[Intro]", plainText: "--- INTRO (4 Takts) ---", chords: [ChordMarker(chord: "Am", characterIndex: 0), ChordMarker(chord: "F", characterIndex: 8), ChordMarker(chord: "C", characterIndex: 16), ChordMarker(chord: "G", characterIndex: 22)]),
            LyricLine(timestamp: 4.0, rawText: "[Am]Welcome to [F]StageFlow on macOS", plainText: "Welcome to StageFlow on macOS", chords: [ChordMarker(chord: "Am", characterIndex: 0), ChordMarker(chord: "F", characterIndex: 11)]),
            LyricLine(timestamp: 8.0, rawText: "[C]Live performance [G]mixer & prompter", plainText: "Live performance mixer & prompter", chords: [ChordMarker(chord: "C", characterIndex: 0), ChordMarker(chord: "G", characterIndex: 16)]),
            LyricLine(timestamp: 12.0, rawText: "[Am]Two separate mix buses: [F]FOH & In-Ear", plainText: "Two separate mix buses: FOH & In-Ear", chords: [ChordMarker(chord: "Am", characterIndex: 0), ChordMarker(chord: "F", characterIndex: 25)]),
            LyricLine(timestamp: 16.0, rawText: "[C]Ultra low latency [G]Apple Silicon audio", plainText: "Ultra low latency Apple Silicon audio", chords: [ChordMarker(chord: "C", characterIndex: 0), ChordMarker(chord: "G", characterIndex: 18)])
        ]
    }
}
