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
    
    private var activeLineID: UUID? {
        LyricLine.activeLineID(in: lyrics, at: currentTime)
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
                                let isCurrent = (line.id == activeLineID)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    if line.plainText.isEmpty && line.chords.isEmpty {
                                        Spacer().frame(height: 16)
                                    } else if line.chords.isEmpty {
                                        // Обычная текстовая строка без аккордов
                                        Text(line.plainText)
                                            .font(.system(size: appState.prompterFontSize, weight: isCurrent ? .heavy : .medium, design: .monospaced))
                                            .foregroundColor(isCurrent ? .white : .gray.opacity(0.65))
                                    } else {
                                        // Точное вертикальное позиционирование аккордов над слогами (E10.8)
                                        HStack(alignment: .bottom, spacing: 0) {
                                            ForEach(line.segments) { seg in
                                                VStack(alignment: .leading, spacing: 2) {
                                                    if let chord = seg.chord, !chord.isEmpty {
                                                        Text(chord)
                                                            .font(.system(size: appState.prompterFontSize * 0.72, weight: .bold, design: .monospaced))
                                                            .foregroundColor(.orange)
                                                    } else {
                                                        Text(" ")
                                                            .font(.system(size: appState.prompterFontSize * 0.72, weight: .bold, design: .monospaced))
                                                    }
                                                    
                                                    Text(seg.text)
                                                        .font(.system(size: appState.prompterFontSize, weight: isCurrent ? .heavy : .medium, design: .monospaced))
                                                        .foregroundColor(isCurrent ? .white : .gray.opacity(0.65))
                                                }
                                            }
                                        }
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
                // E10.9: Скроллить строго при смене activeLineID, исключая лишние анимации на каждом тике
                .onChange(of: currentTime) { newTime in
                    guard appState.autoScrollEnabled, !lyrics.isEmpty else { return }
                    
                    let currentActive = LyricLine.activeLineID(in: lyrics, at: newTime)
                    if currentActive != appState.lastScrolledLineID {
                        appState.lastScrolledLineID = currentActive
                        if let activeID = currentActive {
                            PerformanceSignposts.shared.emitEvent("PrompterAutoScroll")
                            withAnimation(.easeInOut(duration: 0.35)) {
                                proxy.scrollTo(activeID, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }
}
