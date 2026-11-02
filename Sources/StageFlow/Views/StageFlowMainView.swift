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
                        .fill(onAirColor)
                        .frame(width: 8, height: 8)
                    Text(onAirText)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(onAirColor)
                    
                    // MIDI Indicator
                    Image(systemName: "pianokeys")
                        .font(.system(size: 11))
                        .foregroundColor(midi.connectedDeviceName.contains("No") ? .gray : .cyan)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(nsColor: NSColor.windowBackgroundColor))
                
                Divider()
                
                // Переключатель вкладок левой панели: Микшер / Плейлист / Диагностика
                Picker("", selection: $appState.selectedTab) {
                    Text("Live Mixer 🎛️").tag(0)
                    Text("Setlist 📜 (\(appState.playlist.count))").tag(1)
                    Text("Diagnostics 🩺").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(8)
                
                if appState.selectedTab == 0 {
                    // Секция микшеров (FOH Speakers + IEM In-Ear)
                    ScrollView {
                        VStack(spacing: 14) {
                            // 1. Backing Track Channel Strip
                            VStack(spacing: 8) {
                                HStack(spacing: 6) {
                                    Text("BACKING TRACK 🎵")
                                        .font(.system(size: 11, weight: .heavy))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Button(audio.trackIsMuted ? "MUTED" : "MUTE") {
                                        audio.trackIsMuted.toggle()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(audio.trackIsMuted ? .red : .gray.opacity(0.5))
                                    .controlSize(.mini)
                                    
                                    Button("SOLO") {
                                        audio.trackIsSolo.toggle()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(audio.trackIsSolo ? .yellow : .gray.opacity(0.5))
                                    .foregroundColor(audio.trackIsSolo ? .black : .white)
                                    .controlSize(.mini)
                                }
                                
                                HStack(spacing: 12) {
                                    VerticalFader(title: "FOH Out", value: $audio.trackFOHVolume, peak: audio.backingPeak, isClipping: audio.backingClipping, tintColor: .blue)
                                    VerticalFader(title: "In-Ear", value: $audio.trackIEMVolume, peak: audio.backingPeak, isClipping: audio.backingClipping, tintColor: .purple)
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
                                VerticalFader(title: "FOH MASTER", value: $audio.masterFOHVolume, peak: audio.fohPeak, isClipping: audio.fohClipping, tintColor: .blue, isMaster: true)
                                VerticalFader(title: "IEM MASTER", value: $audio.masterIEMVolume, peak: audio.iemPeak, isClipping: audio.iemClipping, tintColor: .purple, isMaster: true)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.08)))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.3), lineWidth: 1))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                } else if appState.selectedTab == 1 {
                    PlaylistView(appState: appState) { track in
                        loadTrackIntoEngine(track)
                    }
                } else {
                    DiagnosticsView(audio: audio, midi: midi)
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
            if appState.selectedTrackID == nil, let first = appState.playlist.first {
                appState.selectedTrackID = first.id
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
    
    private var onAirColor: Color {
        if audio.isOnAir {
            return .green
        }
        switch audio.engineLifecycleState {
        case .failed:
            return .red
        case .degraded:
            return .yellow
        case .starting:
            return .blue
        case .stopped:
            return .gray
        case .ready, .running:
            return .orange
        }
    }
    
    private var onAirText: String {
        if audio.isOnAir {
            return "ON AIR"
        }
        switch audio.engineLifecycleState {
        case .failed:
            return "ENGINE FAILED"
        case .degraded:
            return audio.isPlaying ? "ON AIR (DEGRADED)" : "DEGRADED"
        case .starting:
            return "STARTING"
        case .stopped:
            return "STOPPED"
        case .ready, .running:
            return "PAUSED"
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
