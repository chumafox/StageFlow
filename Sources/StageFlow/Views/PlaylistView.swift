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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(nsColor: NSColor.controlBackgroundColor).opacity(0.3))
            
            Divider()
            
            List(selection: $appState.selectedTrackID) {
                ForEach(appState.playlist) { track in
                    HStack(spacing: 8) {
                        Image(systemName: appState.selectedTrackID == track.id ? "music.note" : "circle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(appState.selectedTrackID == track.id ? .accentColor : .gray.opacity(0.4))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.system(size: 12, weight: appState.selectedTrackID == track.id ? .bold : .regular))
                                .foregroundColor(appState.selectedTrackID == track.id ? .accentColor : .primary)
                                .lineLimit(1)
                            
                            Text(track.artist)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(formatDuration(track.duration))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.selectedTrackID = track.id
                        onTrackSelected(track)
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
            for url in panel.urls {
                let title = url.deletingPathExtension().lastPathComponent
                let lyrics = LyricsParser.extractLyrics(from: url)
                let newTrack = SongTrack(title: title, fileURL: url, duration: 180, lyrics: lyrics)
                appState.playlist.append(newTrack)
                if appState.selectedTrackID == nil {
                    appState.selectedTrackID = newTrack.id
                    onTrackSelected(newTrack)
                }
            }
        }
    }
    
    private func formatDuration(_ sec: TimeInterval) -> String {
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
