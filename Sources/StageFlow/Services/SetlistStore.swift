import Foundation

/// Сервис атомарного сохранения и загрузки сетлиста, настроек и маппингов (E11.5 - E11.9).
public final class SetlistStore: SetlistStoreProtocol, Sendable {
    public let storageURL: URL
    
    public init(storageURL: URL? = nil) {
        if let customURL = storageURL {
            self.storageURL = customURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let dir = appSupport.appendingPathComponent("StageFlow", isDirectory: true)
            self.storageURL = dir.appendingPathComponent("setlist.json")
        }
    }
    
    /// Атомарно сохраняет данные сетлиста на диск (E11.5 / E11.6).
    public func save(setlist: SetlistData) throws {
        let parentDir = storageURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(setlist)
        
        // Атомарная запись через временный файл в той же директории (E11.6)
        let tempURL = parentDir.appendingPathComponent("setlist.tmp.\(UUID().uuidString)")
        try data.write(to: tempURL, options: .atomic)
        
        if FileManager.default.fileExists(atPath: storageURL.path) {
            _ = try FileManager.default.replaceItemAt(storageURL, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: storageURL)
        }
    }
    
    /// Загружает данные сетлиста, проверяет доступность файлов и восстанавливает закладки (E11.5 / E11.7).
    public func load() -> SetlistData? {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            var setlist = try decoder.decode(SetlistData.self, from: data)
            
            // E11.7: Проверка доступности аудиофайлов и резолвинг bookmarks
            for i in 0..<setlist.tracks.count {
                var track = setlist.tracks[i]
                
                // 1. Попытка восстановить из security-scoped bookmark (E11.8)
                if let bData = track.bookmarkData {
                    var isStale = false
                    if let resolved = try? URL(
                        resolvingBookmarkData: bData,
                        options: .withSecurityScope,
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    ), FileManager.default.fileExists(atPath: resolved.path) {
                        track.fileURL = resolved
                        track.isAvailable = true
                        setlist.tracks[i] = track
                        continue
                    }
                }
                
                // 2. Проверка прямого пути
                if let url = track.fileURL {
                    if FileManager.default.fileExists(atPath: url.path) {
                        track.isAvailable = true
                    } else {
                        // Файл перемещён или отсутствует — не удаляем, помечаем недоступным
                        track.isAvailable = false
                    }
                } else {
                    // Виртуальный или demo-трек
                    track.isAvailable = true
                }
                
                setlist.tracks[i] = track
            }
            
            return setlist
        } catch {
            // E11.6: Повреждённый JSON — создаём резервную копию и не крашимся
            handleCorruptStore(error: error)
            return nil
        }
    }
    
    /// Создаёт аварийный бэкап повреждённого файла для расследования (E11.6).
    private func handleCorruptStore(error: Error) {
        let parentDir = storageURL.deletingLastPathComponent()
        let timestamp = Int(Date().timeIntervalSince1970)
        let backupURL = parentDir.appendingPathComponent("setlist.corrupt.\(timestamp).bak")
        try? FileManager.default.copyItem(at: storageURL, to: backupURL)
    }
}
