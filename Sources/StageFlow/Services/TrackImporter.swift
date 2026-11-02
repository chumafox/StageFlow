import Foundation
import AVFoundation

/// Сервис асинхронного импорта треков и пакетной обработки (E11.1 / E11.2 / E11.3).
public final class TrackImporter: TrackImporterProtocol, Sendable {
    public static let shared = TrackImporter()
    
    public init() {}
    
    private static let supportedExtensions: Set<String> = [
        "wav", "mp3", "m4a", "aif", "aiff", "aac", "caf", "flac"
    ]
    
    /// Асинхронно импортирует аудиофайл, извлекая реальную длительность, метаданные и тексты (E11.1 / E11.2).
    public func importTrack(from url: URL) async throws -> SongTrack {
        let signpost = PerformanceSignposts.shared.beginInterval("TrackImport")
        defer { PerformanceSignposts.shared.endInterval("TrackImport", state: signpost) }
        
        // 1. Проверка существования файла на диске (E11.7 / SF-11)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StageFlowError.missingFile(url.path)
        }
        
        // 2. Проверка поддерживаемого формата
        let ext = url.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            throw StageFlowError.unsupportedFileType(".\(ext)")
        }
        
        let asset = AVURLAsset(url: url)
        
        // 3. Достоверное извлечение длительности (E11.2: убрать вымышленные 180 с)
        let durationSec: Double
        do {
            let cmDuration = try await asset.load(.duration)
            let sec = CMTimeGetSeconds(cmDuration)
            if sec.isNaN || sec <= 0 {
                if let af = try? AVAudioFile(forReading: url) {
                    let sr = af.processingFormat.sampleRate
                    let len = af.length
                    durationSec = sr > 0 ? Double(len) / sr : 0.0
                } else {
                    throw StageFlowError.corruptFile("Zero or invalid duration in \(url.lastPathComponent)")
                }
            } else {
                durationSec = sec
            }
        } catch let err as StageFlowError {
            throw err
        } catch {
            if let af = try? AVAudioFile(forReading: url) {
                let sr = af.processingFormat.sampleRate
                let len = af.length
                durationSec = sr > 0 ? Double(len) / sr : 0.0
            } else {
                throw StageFlowError.corruptFile("Failed to load duration for \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        
        // 4. Чтение встроенных метаданных названия и исполнителя
        var trackTitle = url.deletingPathExtension().lastPathComponent
        var trackArtist = "Live"
        
        if let metadata = try? await asset.load(.metadata) {
            for item in metadata {
                if let commonKey = item.commonKey {
                    if commonKey == .commonKeyTitle {
                        if let val = try? await item.load(.stringValue), !val.trimmingCharacters(in: .whitespaces).isEmpty {
                            trackTitle = val
                        }
                    } else if commonKey == .commonKeyArtist {
                        if let val = try? await item.load(.stringValue), !val.trimmingCharacters(in: .whitespaces).isEmpty {
                            trackArtist = val
                        }
                    }
                }
            }
        }
        
        // 5. Асинхронное извлечение текстов и аккордов
        let lyrics = await LyricsParser.extractLyricsAsync(from: url)
        
        // 6. Создание security-scoped bookmark для песочницы macOS (E11.8)
        let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        
        return SongTrack(
            title: trackTitle,
            artist: trackArtist,
            fileURL: url,
            duration: durationSec,
            lyrics: lyrics,
            bookmarkData: bookmarkData,
            isAvailable: true
        )
    }
    
    /// Пакетный асинхронный импорт с ограничением параллелизма и отслеживанием прогресса (E11.3).
    public func importBatch(
        urls: [URL],
        maxConcurrency: Int = 4,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async -> (tracks: [SongTrack], errors: [(url: URL, error: StageFlowError)]) {
        guard !urls.isEmpty else { return ([], []) }
        let concurrency = max(1, min(maxConcurrency, urls.count))
        
        var tracks: [SongTrack] = []
        var errors: [(url: URL, error: StageFlowError)] = []
        
        var completedCount = 0
        let totalCount = urls.count
        
        for chunk in stride(from: 0, to: urls.count, by: concurrency).map({ Array(urls[$0..<min($0 + concurrency, urls.count)]) }) {
            await withTaskGroup(of: (URL, Result<SongTrack, StageFlowError>).self) { group in
                for url in chunk {
                    group.addTask {
                        do {
                            let track = try await self.importTrack(from: url)
                            return (url, .success(track))
                        } catch let sfErr as StageFlowError {
                            return (url, .failure(sfErr))
                        } catch {
                            return (url, .failure(StageFlowError.corruptFile(error.localizedDescription)))
                        }
                    }
                }
                
                for await (url, res) in group {
                    completedCount += 1
                    progressHandler?(Double(completedCount) / Double(totalCount))
                    switch res {
                    case .success(let track):
                        tracks.append(track)
                    case .failure(let err):
                        errors.append((url: url, error: err))
                    }
                }
            }
        }
        
        // Сохраняем исходный порядок файлов из URLs
        let urlOrder = Dictionary(uniqueKeysWithValues: urls.enumerated().map { ($0.element, $0.offset) })
        tracks.sort { (t1, t2) -> Bool in
            guard let u1 = t1.fileURL, let o1 = urlOrder[u1],
                  let u2 = t2.fileURL, let o2 = urlOrder[u2] else { return false }
            return o1 < o2
        }
        
        return (tracks, errors)
    }
}
