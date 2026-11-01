import SwiftUI

public struct StagePrompterView: View {
    public let lyrics: [LyricLine]
    public let currentTime: TimeInterval
    public let duration: TimeInterval
    @ObservedObject public var appState: AppState
    
    public init(lyrics: [LyricLine], currentTime: TimeInterval, duration: TimeInterval, appState: AppState) {
        self.lyrics = lyrics
        self.currentTime = currentTime
        self.duration = duration
        self.appState = appState
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Prompter Header (Zoom controls, status)
            HStack {
                Text("STAGE PROMPTER")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Toggle("Auto-Scroll", isOn: $appState.autoScrollEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                
                Button(action: { appState.prompterFontSize = max(18.0, appState.prompterFontSize - 2.0) }) {
                    Image(systemName: "textformat.size.smaller")
                }
                .buttonStyle(.borderless)
                
                Button(action: { appState.prompterFontSize = min(48.0, appState.prompterFontSize + 2.0) }) {
                    Image(systemName: "textformat.size.larger")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.4))
            
            Divider()
            
            // Lyrics Scroller
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if lyrics.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                                Text("No Lyrics / Chords in this audio file")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity, minHeight: 300)
                        } else {
                            ForEach(lyrics) { line in
                                let isCurrent = isLineActive(line)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    // Chords row (Stage Traxx style gold chords above syllables)
                                    if !line.chords.isEmpty {
                                        Text(line.chords.map { $0.chord }.joined(separator: "    "))
                                            .font(.system(size: appState.prompterFontSize * 0.75, weight: .bold, design: .monospaced))
                                            .foregroundColor(.orange)
                                    }
                                    
                                    // Plain text row
                                    if !line.plainText.isEmpty {
                                        Text(line.plainText)
                                            .font(.system(size: appState.prompterFontSize, weight: isCurrent ? .heavy : .medium))
                                            .foregroundColor(isCurrent ? .white : .gray.opacity(0.55))
                                    } else {
                                        Spacer().frame(height: 16)
                                    }
                                }
                                .id(line.id)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(isCurrent ? Color.accentColor.opacity(0.25) : Color.clear)
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.vertical, 80)
                }
                .onChange(of: currentTime) { newTime in
                    guard appState.autoScrollEnabled, !lyrics.isEmpty else { return }
                    // 1. По временным меткам
                    if let activeLine = lyrics.last(where: { ($0.timestamp ?? -1) >= 0 && ($0.timestamp ?? 0) <= newTime }) {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo(activeLine.id, anchor: .center)
                        }
                    }
                    // 2. Линейный скролл по общей длительности если нет таймкодов
                    else if duration > 0 {
                        let ratio = newTime / duration
                        let targetIndex = min(lyrics.count - 1, Int(Double(lyrics.count) * ratio))
                        let line = lyrics[targetIndex]
                        withAnimation(.easeInOut(duration: 0.4)) {
                            proxy.scrollTo(line.id, anchor: .center)
                        }
                    }
                }
            }
        }
    }
    
    private func isLineActive(_ line: LyricLine) -> Bool {
        guard let time = line.timestamp else { return false }
        return currentTime >= time && currentTime < (time + 3.8)
    }
}
