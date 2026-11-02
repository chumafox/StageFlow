import Foundation
import AVFoundation

/// Результат разбора документа текста песни с метаданными (E10.5 / E10.10).
public struct LyricsDocument: Sendable, Equatable {
    public var title: String?
    public var artist: String?
    public var bpm: Int?
    public var key: String?
    public var capo: Int?
    public var offset: TimeInterval = 0.0 // смещение в секундах
    public var lines: [LyricLine]
    
    public init(
        title: String? = nil,
        artist: String? = nil,
        bpm: Int? = nil,
        key: String? = nil,
        capo: Int? = nil,
        offset: TimeInterval = 0.0,
        lines: [LyricLine] = []
    ) {
        self.title = title
        self.artist = artist
        self.bpm = bpm
        self.key = key
        self.capo = capo
        self.offset = offset
        self.lines = lines
    }
}

public class LyricsParser {
    
    // Регулярное выражение для извлечения временных меток вида [01:23.45] или [01:23:456] (E10.1 / E10.2 / E10.4)
    private static let timeRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#)
        } catch {
            fatalError("Failed to initialize timeRegex: \(error)")
        }
    }()
    
    // Регулярное выражение для метаданных LRC заголовка вида [ti:Title], [ar:Artist], [offset:+500] (E10.3)
    private static let lrcTagRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: #"^\[([a-zA-Z]{1,10}):\s*([^\]]*)\]"#)
        } catch {
            fatalError("Failed to initialize lrcTagRegex: \(error)")
        }
    }()
    
    // Регулярное выражение для директив ChordPro вида {title: ...}, {bpm: 120}, {c: Chorus} (E10.5)
    private static let chordProDirectiveRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: #"^\{([a-zA-Z_]+)(?::\s*([^}]*))?\}"#)
        } catch {
            fatalError("Failed to initialize chordProDirectiveRegex: \(error)")
        }
    }()
    
    // Регулярное выражение для inline аккордов [Am], [C#m7], [G/B] (E10.4 / E10.5)
    private static let chordRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: #"\[([^\]]+)\]"#)
        } catch {
            fatalError("Failed to initialize chordRegex: \(error)")
        }
    }()

    // MARK: - Асинхронная и синхронная загрузка метаданных (E10.6)
    
    /// Асинхронное извлечение текстов без устаревших (deprecated) APIs (E10.6).
    public static func extractLyricsAsync(from fileURL: URL) async -> [LyricLine] {
        let doc = await extractDocumentAsync(from: fileURL)
        return doc.lines.isEmpty ? generateDefaultPlaceholder() : doc.lines
    }
    
    /// Асинхронное извлечение полного документа с метаданными (E10.5 / E10.6).
    public static func extractDocumentAsync(from fileURL: URL) async -> LyricsDocument {
        var rawText: String? = nil
        
        // 1. Попытка чтения встроенных метаданных через современный async API AVFoundation
        let asset = AVURLAsset(url: fileURL)
        if let metadata = try? await asset.load(.metadata) {
            for item in metadata {
                let keyStr = (item.key as? String)?.lowercased() ?? ""
                if item.commonKey?.rawValue == "lyrics" ||
                   item.identifier?.rawValue.contains("USLT") == true ||
                   keyStr.contains("lyric") {
                    if let str = try? await item.load(.stringValue) {
                        rawText = str
                        if !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { break }
                    }
                }
            }
        }
        
        // 2. Внешние файлы .lrc или .txt
        if rawText == nil {
            rawText = loadExternalLyricsText(fileURL: fileURL)
        }
        
        guard let text = rawText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return LyricsDocument(lines: generateDefaultPlaceholder())
        }
        
        return parseDocument(text)
    }

    /// Синхронная точка входа для существующего UI с безопасным вызовом (E10.6).
    public static func extractLyrics(from fileURL: URL) -> [LyricLine] {
        if let externalText = loadExternalLyricsText(fileURL: fileURL) {
            return parseChordPro(externalText)
        }
        
        var result: [LyricLine]? = nil
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            result = await extractLyricsAsync(from: fileURL)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2.0)
        return result ?? generateDefaultPlaceholder()
    }
    
    private static func loadExternalLyricsText(fileURL: URL) -> String? {
        let lrcURL = fileURL.deletingPathExtension().appendingPathExtension("lrc")
        let txtURL = fileURL.deletingPathExtension().appendingPathExtension("txt")
        
        if FileManager.default.fileExists(atPath: lrcURL.path) {
            if let text = try? String(contentsOf: lrcURL, encoding: .utf8) {
                return text
            }
            // Fallback на Windows-1251 для русских текстов (E10.8)
            let cstr = (try? String(contentsOf: lrcURL, encoding: .windowsCP1251))
            if let c = cstr { return c }
        }
        if FileManager.default.fileExists(atPath: txtURL.path) {
            if let text = try? String(contentsOf: txtURL, encoding: .utf8) {
                return text
            }
            let cstr = (try? String(contentsOf: txtURL, encoding: .windowsCP1251))
            if let c = cstr { return c }
        }
        return nil
    }
    
    // MARK: - Парсинг текста: LRC + ChordPro (E10.1 - E10.5)
    
    /// Парсит текст в массив строк (обратная совместимость).
    public static func parseChordPro(_ text: String) -> [LyricLine] {
        return parseDocument(text).lines
    }
    
    /// Парсит документ с метаданными, поддержкой множественных меток, долей секунд и ChordPro.
    public static func parseDocument(_ text: String) -> LyricsDocument {
        var doc = LyricsDocument()
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return doc
        }
        var unsortedLines: [LyricLine] = []
        let rawLines = text.components(separatedBy: .newlines)
        
        let timeRegex = Self.timeRegex
        let lrcTagRegex = Self.lrcTagRegex
        let chordProDirectiveRegex = Self.chordProDirectiveRegex
        let chordRegex = Self.chordRegex
        
        for rawLine in rawLines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                unsortedLines.append(LyricLine(timestamp: nil, rawText: "", plainText: "", chords: []))
                continue
            }
            
            let lineRange = NSRange(trimmed.startIndex..., in: trimmed)
            
            // 1. Проверка директив ChordPro вида {title: ...}, {bpm: ...}, {c: ...} (E10.5)
            if let dirMatch = chordProDirectiveRegex.firstMatch(in: trimmed, range: lineRange) {
                if let nameRange = Range(dirMatch.range(at: 1), in: trimmed) {
                    let dirName = String(trimmed[nameRange]).lowercased()
                    var dirValue: String? = nil
                    if dirMatch.numberOfRanges > 2, dirMatch.range(at: 2).location != NSNotFound,
                       let valRange = Range(dirMatch.range(at: 2), in: trimmed) {
                        dirValue = String(trimmed[valRange]).trimmingCharacters(in: .whitespaces)
                    }
                    
                    switch dirName {
                    case "title", "t":
                        doc.title = dirValue
                    case "artist", "a":
                        doc.artist = dirValue
                    case "bpm":
                        if let v = dirValue, let b = Int(v) { doc.bpm = b }
                    case "key":
                        doc.key = dirValue
                    case "capo":
                        if let v = dirValue, let c = Int(v) { doc.capo = c }
                    case "comment", "c":
                        // Комментарии/секции оформляются как заметка
                        if let comment = dirValue {
                            unsortedLines.append(LyricLine(timestamp: nil, rawText: trimmed, plainText: "--- \(comment.uppercased()) ---", chords: []))
                        }
                    default:
                        break
                    }
                }
                continue
            }
            
            // 2. Проверка метаданных LRC заголовка вида [ti:Title], [ar:Artist], [offset:+500] (E10.3)
            if let tagMatch = lrcTagRegex.firstMatch(in: trimmed, range: lineRange) {
                if let tagRange = Range(tagMatch.range(at: 1), in: trimmed),
                   let valRange = Range(tagMatch.range(at: 2), in: trimmed) {
                    let tag = String(trimmed[tagRange]).lowercased()
                    let value = String(trimmed[valRange]).trimmingCharacters(in: .whitespaces)
                    
                    switch tag {
                    case "ti": doc.title = value
                    case "ar": doc.artist = value
                    case "offset":
                        // E10.3: Смещение в миллисекундах (+/-)
                        if let ms = Int(value) {
                            doc.offset = Double(ms) / 1000.0
                        }
                    default:
                        break
                    }
                }
                continue
            }
            
            // 3. Извлечение ВСЕХ временных меток строки (E10.2 / E10.4)
            var timestamps: [TimeInterval] = []
            let timeMatches = timeRegex.matches(in: trimmed, range: lineRange)
            for m in timeMatches {
                if let minRange = Range(m.range(at: 1), in: trimmed),
                   let secRange = Range(m.range(at: 2), in: trimmed) {
                    let mins = Double(trimmed[minRange]) ?? 0.0
                    let secs = Double(trimmed[secRange]) ?? 0.0
                    var fraction = 0.0
                    
                    // E10.1 / E10.2: Точный расчёт долей секунды (1 digit -> /10, 2 digits -> /100, 3 digits -> /1000)
                    if m.numberOfRanges > 3, m.range(at: 3).location != NSNotFound,
                       let fracRange = Range(m.range(at: 3), in: trimmed) {
                        let fracStr = String(trimmed[fracRange])
                        if let val = Double(fracStr) {
                            let divisor = pow(10.0, Double(max(1, fracStr.count)))
                            fraction = val / divisor
                        }
                    }
                    timestamps.append((mins * 60.0) + secs + fraction)
                }
            }
            
            // Очищаем строку от временных меток
            let textWithoutTimes = timeRegex.stringByReplacingMatches(
                in: trimmed,
                range: lineRange,
                withTemplate: ""
            ).trimmingCharacters(in: .whitespaces)
            
            // 4. Парсинг аккордов [Am], [C#m7], [G/B] (E10.4 / E10.5)
            var chords: [ChordMarker] = []
            var cleanText = ""
            var lastIdx = textWithoutTimes.startIndex
            
            let chordMatches = chordRegex.matches(in: textWithoutTimes, range: NSRange(textWithoutTimes.startIndex..., in: textWithoutTimes))
            for cm in chordMatches {
                if let chordRange = Range(cm.range(at: 1), in: textWithoutTimes),
                   let fullRange = Range(cm.range(at: 0), in: textWithoutTimes) {
                    cleanText += textWithoutTimes[lastIdx..<fullRange.lowerBound]
                    let chordName = String(textWithoutTimes[chordRange])
                    chords.append(ChordMarker(chord: chordName, characterIndex: cleanText.count))
                    lastIdx = fullRange.upperBound
                }
            }
            cleanText += textWithoutTimes[lastIdx...]
            
            // 5. Формирование строк (E10.4: для каждого timestamp создается отдельная запись)
            if timestamps.isEmpty {
                unsortedLines.append(LyricLine(timestamp: nil, rawText: rawLine, plainText: cleanText, chords: chords))
            } else {
                for ts in timestamps {
                    unsortedLines.append(LyricLine(timestamp: ts, rawText: rawLine, plainText: cleanText, chords: chords))
                }
            }
        }
        
        // 6. Применение LRC offset и хронологическая сортировка (E10.3 / E10.4)
        var finalLines: [LyricLine] = []
        let offset = doc.offset
        
        for line in unsortedLines {
            if let t = line.timestamp {
                let adjustedTime = max(0.0, t + offset)
                finalLines.append(LyricLine(id: line.id, timestamp: adjustedTime, rawText: line.rawText, plainText: line.plainText, chords: line.chords))
            } else {
                finalLines.append(line)
            }
        }
        
        // Сортировка: сначала синхронизированные по времени, затем без меток
        finalLines.sort { lhs, rhs in
            switch (lhs.timestamp, rhs.timestamp) {
            case let (l?, r?): return l < r
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return false
            }
        }
        
        doc.lines = finalLines
        return doc
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
