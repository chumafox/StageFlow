import SwiftUI

public struct StageFlowMainView: View {
    @StateObject private var audio = LiveAudioEngine()
    @StateObject private var midi = MIDIManager.shared
    @StateObject private var appState = AppState()
    
    public init() {}
    
    public var body: some View {
        HSplitView {
            // Левая панель: Сетлист + Микшер (FOH / In-Ear)
            VStack(spacing: 0) {
                // Header Bar
                HStack(spacing: 10) {
                    Text("STAGEFLOW")
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundColor(.accentColor)
                    
                    Spacer()
                    
                    Circle()
                        .fill(audio.isPlaying ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(audio.isPlaying ? "ON AIR" : "PAUSED")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(audio.isPlaying ? .green : .orange)
                    
                    // MIDI Indicator
                    Image(systemName: "pianokeys")
                        .font(.system(size: 11))
                        .foregroundColor(midi.connectedDeviceName.contains("No") ? .gray : .cyan)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(nsColor: NSColor.windowBackgroundColor))
                
                Divider()
                
                // Переключатель вкладок левой панели: Микшер / Плейлист
                Picker("", selection: $appState.selectedTab) {
                    Text("Live Mixer 🎛️").tag(0)
                    Text("Setlist 📜 (\(appState.playlist.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(8)
                
                if appState.selectedTab == 0 {
                    // Секция микшеров (FOH Speakers + IEM In-Ear)
                    ScrollView {
                        VStack(spacing: 14) {
                            // 1. Backing Track Channel Strip
                            VStack(spacing: 8) {
                                HStack {
                                    Text("BACKING TRACK 🎵")
                                        .font(.system(size: 11, weight: .heavy))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text(appState.selectedTrack?.title ?? "Demo Loop")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                
                                HStack(spacing: 12) {
                                    VerticalFader(title: "FOH Out", value: $audio.trackFOHVolume, peak: audio.fohPeak, tintColor: .blue)
                                    VerticalFader(title: "In-Ear", value: $audio.trackIEMVolume, peak: audio.iemPeak, tintColor: .purple)
                                    Spacer()
                                }
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: NSColor.controlBackgroundColor).opacity(0.3)))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
                            
                            // 2. Microphones with CoreAudio DSP
                            MicStripCard(mic: audio.mic1, title: "MIC 1 (LEAD) 🎤")
                            MicStripCard(mic: audio.mic2, title: "MIC 2 (BACKING) 🎙️")
                            
                            // 3. Master Section
                            HStack(spacing: 12) {
                                VerticalFader(title: "FOH MASTER", value: $audio.masterFOHVolume, peak: audio.fohPeak, tintColor: .blue, isMaster: true)
                                VerticalFader(title: "IEM MASTER", value: $audio.masterIEMVolume, peak: audio.iemPeak, tintColor: .purple, isMaster: true)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.08)))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.3), lineWidth: 1))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                } else {
                    PlaylistView(appState: appState) { track in
                        loadTrackIntoEngine(track)
                    }
                }
                
                Divider()
                
                // Транспортная панель (Play, Time, Seek)
                TransportBar(audio: audio, currentSong: appState.selectedTrack?.title ?? "Demo Loop")
            }
            .frame(minWidth: 340, maxWidth: 420)
            
            // Правая панель: Сценический экран суфлера (Stage Prompter)
            StagePrompterView(
                lyrics: appState.selectedTrack?.lyrics ?? appState.playlist.first?.lyrics ?? [],
                currentTime: audio.currentTrackTime,
                duration: audio.trackDuration,
                appState: appState
            )
            .background(Color.black)
        }
        .frame(minWidth: 960, minHeight: 640)
        .onAppear {
            if appState.selectedTrack == nil, let first = appState.playlist.first {
                appState.selectedTrack = first
            }
            setupMIDIBindings()
        }
    }
    
    private func loadTrackIntoEngine(_ track: SongTrack) {
        if let url = track.fileURL {
            audio.loadAudioFile(url: url)
        }
    }
    
    private func setupMIDIBindings() {
        midi.onPlayPauseTrigger = {
            audio.togglePlayPause()
        }
        midi.onVolumeChange = { target, value in
            switch target {
            case "masterFOH":
                audio.masterFOHVolume = value
            case "reverb":
                audio.mic1.reverbSend = value
            default:
                break
            }
        }
    }
}

// MARK: - Транспортная панель
struct TransportBar: View {
    @ObservedObject var audio: LiveAudioEngine
    var currentSong: String
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Button(action: { audio.togglePlayPause() }) {
                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderedProminent)
                .tint(audio.isPlaying ? .orange : .green)
                .keyboardShortcut(.space, modifiers: [])
                
                Button(action: { audio.stop() }) {
                    Image(systemName: "stop.fill")
                        .font(.body)
                }
                .buttonStyle(.bordered)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentSong)
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                    
                    Text("\(formatTime(audio.currentTrackTime)) / \(formatTime(audio.trackDuration))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Прогресс-бар воспроизведения
            Slider(value: Binding(
                get: { audio.currentTrackTime },
                set: { audio.seek(to: $0) }
            ), in: 0.0...max(audio.trackDuration, 1.0))
            .controlSize(.mini)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: NSColor.windowBackgroundColor))
    }
    
    private func formatTime(_ sec: TimeInterval) -> String {
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
