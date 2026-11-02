import Foundation
import SwiftUI

@MainActor
public class AppState: ObservableObject {
    public let setlistStore: SetlistStoreProtocol
    public let trackImporter: TrackImporterProtocol
    
    @Published public var playlist: [SongTrack] = []
    @Published public var selectedTrackID: UUID? = nil
    @Published public var selectedTab: Int = 0 // 0: Mixer, 1: Playlist, 2: Diagnostics
    
    // Prompter settings
    @Published public var prompterFontSize: CGFloat = 28.0
    @Published public var autoScrollEnabled: Bool = true
    @Published public var lastScrolledLineID: UUID? = nil
    
    // Import state (E11.3)
    @Published public var isImporting: Bool = false
    @Published public var importProgress: Double = 0.0
    @Published public var lastImportErrors: [(url: URL, error: StageFlowError)] = []
    
    public var selectedTrack: SongTrack? {
        guard let id = selectedTrackID else { return nil }
        return playlist.first { $0.id == id }
    }
    
    public init(
        setlistStore: SetlistStoreProtocol = SetlistStore(),
        trackImporter: TrackImporterProtocol = TrackImporter.shared,
        autoLoad: Bool = false
    ) {
        self.setlistStore = setlistStore
        self.trackImporter = trackImporter
        
        if autoLoad {
            loadSavedSetlist()
        }
        
        // Если после загрузки плейлист пуст, добавляем дефолтный демо-трек
        if self.playlist.isEmpty {
            let demo = SongTrack(
                title: "StageFlow Demo Song",
                artist: "Apple Silicon Live",
                duration: 20.0,
                lyrics: LyricsParser.generateDefaultPlaceholder()
            )
            self.playlist = [demo]
            self.selectedTrackID = demo.id
        }
    }
    
    // MARK: - Плейлист и выбор треков
    
    public func selectTrack(id: UUID?) {
        self.selectedTrackID = id
        saveCurrentSetlist()
    }
    
    public func selectTrack(_ track: SongTrack) {
        self.selectedTrackID = track.id
        saveCurrentSetlist()
    }
    
    /// Выбирает следующий трек в плейлисте (E09.8).
    public func selectNextTrack() {
        guard let currentID = selectedTrackID,
              let currentIndex = playlist.firstIndex(where: { $0.id == currentID }),
              currentIndex + 1 < playlist.count else { return }
        selectedTrackID = playlist[currentIndex + 1].id
        saveCurrentSetlist()
    }
    
    /// Выбирает предыдущий трек в плейлисте (E09.8).
    public func selectPreviousTrack() {
        guard let currentID = selectedTrackID,
              let currentIndex = playlist.firstIndex(where: { $0.id == currentID }),
              currentIndex > 0 else { return }
        selectedTrackID = playlist[currentIndex - 1].id
        saveCurrentSetlist()
    }
    
    /// Удаляет трек по ID из плейлиста (E11.4).
    public func removeTrack(id: UUID) {
        guard let index = playlist.firstIndex(where: { $0.id == id }) else { return }
        playlist.remove(at: index)
        if selectedTrackID == id {
            selectedTrackID = playlist.indices.contains(index) ? playlist[index].id : playlist.last?.id
        }
        saveCurrentSetlist()
    }
    
    // MARK: - Асинхронный импорт и связывание (E11.1 - E11.4, E11.7)
    
    /// Асинхронный импорт файлов в плейлист (E11.1 / E11.3).
    public func importTracks(urls: [URL]) async {
        guard !urls.isEmpty else { return }
        
        isImporting = true
        importProgress = 0.0
        lastImportErrors = []
        
        let result = await trackImporter.importBatch(urls: urls, maxConcurrency: 4) { [weak self] progress in
            Task { @MainActor in
                self?.importProgress = progress
            }
        }
        
        // E11.4: Обновление плейлиста без дублирования состояния
        for track in result.tracks {
            // Если трек с таким файлом уже есть, обновляем его
            if let existingIndex = playlist.firstIndex(where: { $0.fileURL == track.fileURL }) {
                playlist[existingIndex] = track
            } else {
                playlist.append(track)
            }
        }
        
        if selectedTrackID == nil || !playlist.contains(where: { $0.id == selectedTrackID }) {
            selectedTrackID = result.tracks.first?.id ?? playlist.first?.id
        }
        
        lastImportErrors = result.errors
        isImporting = false
        saveCurrentSetlist()
    }
    
    /// Повторное связывание недоступного файла с новым путем (E11.7).
    public func relinkTrack(id: UUID, newURL: URL) async {
        guard let index = playlist.firstIndex(where: { $0.id == id }) else { return }
        do {
            let updated = try await trackImporter.importTrack(from: newURL)
            playlist[index] = SongTrack(
                id: id,
                title: playlist[index].title,
                artist: updated.artist,
                fileURL: newURL,
                duration: updated.duration,
                lyrics: updated.lyrics,
                bookmarkData: updated.bookmarkData,
                isAvailable: true
            )
            saveCurrentSetlist()
        } catch {
            playlist[index].isAvailable = false
        }
    }
    
    // MARK: - Персистентность (E11.5 / E11.6 / E11.9)
    
    public func saveCurrentSetlist() {
        let setlist = SetlistData(
            schemaVersion: 1,
            tracks: playlist,
            selectedTrackID: selectedTrackID,
            prompterFontSize: Double(prompterFontSize),
            autoScrollEnabled: autoScrollEnabled,
            midiMappings: MIDIMappingStore.shared.userMappings
        )
        try? setlistStore.save(setlist: setlist)
    }
    
    public func loadSavedSetlist() {
        guard let data = setlistStore.load() else { return }
        
        self.playlist = data.tracks
        self.prompterFontSize = CGFloat(data.prompterFontSize)
        self.autoScrollEnabled = data.autoScrollEnabled
        
        if let selID = data.selectedTrackID, playlist.contains(where: { $0.id == selID }) {
            self.selectedTrackID = selID
        } else {
            self.selectedTrackID = playlist.first?.id
        }
    }
}
