import SwiftUI
import UniformTypeIdentifiers

public struct PlaylistView: View {
    @ObservedObject public var appState: AppState
    public var onTrackSelected: (SongTrack) -> Void
    
    public init(appState: AppState, onTrackSelected: @escaping (SongTrack) -> Void) {
        self.appState = appState
        self.onTrackSelected = onTrackSelected
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("SETLIST / PLAYLIST")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: openFilePicker) {
                    Label("Add Track", systemImage: "plus")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appState.isImporting)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(nsColor: NSColor.controlBackgroundColor).opacity(0.3))
            
            // Progress Bar for Batch Import (E11.3)
            if appState.isImporting {
                ProgressView(value: appState.importProgress)
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
            }
            
            Divider()
            
            // Tracks List
            List(selection: $appState.selectedTrackID) {
                ForEach(appState.playlist) { track in
                    HStack(spacing: 8) {
                        if !track.isAvailable {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                        } else {
                            Image(systemName: appState.selectedTrackID == track.id ? "music.note" : "circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(appState.selectedTrackID == track.id ? .accentColor : .gray.opacity(0.4))
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.system(size: 12, weight: appState.selectedTrackID == track.id ? .bold : .regular))
                                .foregroundColor(!track.isAvailable ? .secondary : (appState.selectedTrackID == track.id ? .accentColor : .primary))
                                .lineLimit(1)
                            
                            if !track.isAvailable {
                                Text("File missing — click to relink")
                                    .font(.system(size: 10))
                                    .foregroundColor(.yellow)
                            } else {
                                Text(track.artist)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if !track.isAvailable {
                            Button("Relink") {
                                relink(track: track)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        } else {
                            Text(formatDuration(track.duration))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.selectTrack(track)
                        if track.isAvailable {
                            onTrackSelected(track)
                        }
                    }
                    .contextMenu {
                        if !track.isAvailable {
                            Button("Relink Audio File...") {
                                relink(track: track)
                            }
                        }
                        Button("Remove from Setlist", role: .destructive) {
                            appState.removeTrack(id: track.id)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }
    
    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [.audio, .mp3, .aiff, .wav]
        
        if panel.runModal() == .OK {
            let urls = panel.urls
            Task { @MainActor in
                await appState.importTracks(urls: urls)
                if let selected = appState.selectedTrack, selected.isAvailable {
                    onTrackSelected(selected)
                }
            }
        }
    }
    
    private func relink(track: SongTrack) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [.audio, .mp3, .aiff, .wav]
        panel.message = "Locate audio file for '\(track.title)'"
        
        if panel.runModal() == .OK, let url = panel.url {
            Task { @MainActor in
                await appState.relinkTrack(id: track.id, newURL: url)
                if let updated = appState.selectedTrack, updated.id == track.id, updated.isAvailable {
                    onTrackSelected(updated)
                }
            }
        }
    }
    
    private func formatDuration(_ sec: TimeInterval) -> String {
        guard sec > 0 else { return "--:--" }
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
