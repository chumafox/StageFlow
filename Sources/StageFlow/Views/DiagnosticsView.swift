import SwiftUI
import AVFoundation

public struct DiagnosticsView: View {
    @ObservedObject public var audio: LiveAudioEngine
    @ObservedObject public var midi: MIDIManager
    
    public init(audio: LiveAudioEngine, midi: MIDIManager) {
        self.audio = audio
        self.midi = midi
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Заголовок
                HStack {
                    Text("ENGINE DIAGNOSTICS & SYSTEM STATUS")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundColor(.primary)
                    Spacer()
                    Button("Reconfigure Graph") {
                        audio.handleConfigurationChange()
                    }
                    .controlSize(.small)
                }
                .padding(.bottom, 4)
                
                // 1. Статус движка
                GroupBox(label: Label("Audio Engine Lifecycle (E08.3)", systemImage: "bolt.fill")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Engine State:")
                                .font(.system(size: 11, weight: .bold))
                            Spacer()
                            Text(audio.engineLifecycleState.displayName)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(stateColor)
                        }
                        
                        HStack {
                            Text("ON AIR Status:")
                                .font(.system(size: 11, weight: .bold))
                            Spacer()
                            Text(audio.isOnAir ? "ACTIVE (ON AIR)" : "OFF AIR")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(audio.isOnAir ? .green : .gray)
                        }
                        
                        HStack {
                            Text("Transport State:")
                                .font(.system(size: 11, weight: .bold))
                            Spacer()
                            Text(transportStateDescription)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(6)
                }
                
                // 2. Аудио маршрутизация и оборудование
                GroupBox(label: Label("Audio Routing & Hardware (E08.5 / ADR-001)", systemImage: "speaker.wave.3.fill")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Routing Mode:")
                                .font(.system(size: 11, weight: .bold))
                            Spacer()
                            Text(audio.graphController.isIEMAvailable ? "Quadraphonic (FOH 1-2, IEM 3-4)" : "Stereo Fallback (FOH only)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(audio.graphController.isIEMAvailable ? .green : .orange)
                        }
                        
                        HStack {
                            Text("Hardware Channels:")
                                .font(.system(size: 11, weight: .bold))
                            Spacer()
                            Text("\(audio.graphController.outputChannelCount) channels")
                                .font(.system(size: 11, design: .monospaced))
                        }
                        
                        HStack {
                            Text("Sample Rate:")
                                .font(.system(size: 11, weight: .bold))
                            Spacer()
                            Text(String(format: "%.1f kHz", audio.graphController.stereoFormat.sampleRate / 1000.0))
                                .font(.system(size: 11, design: .monospaced))
                        }
                        
                        HStack {
                            Text("IEM Available:")
                                .font(.system(size: 11, weight: .bold))
                            Spacer()
                            Text(audio.graphController.isIEMAvailable ? "YES (Ch 3-4)" : "NO (Disabled)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(audio.graphController.isIEMAvailable ? .green : .red)
                        }
                    }
                    .padding(6)
                }
                
                // 3. Разрешения микрофона
                GroupBox(label: Label("Microphone Access (E08.6)", systemImage: "mic.fill")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Mic Permission:")
                                .font(.system(size: 11, weight: .bold))
                            Spacer()
                            Text(audio.isMicPermissionGranted ? "AUTHORIZED" : "DENIED / UNAVAILABLE")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(audio.isMicPermissionGranted ? .green : .red)
                        }
                        
                        if !audio.isMicPermissionGranted {
                            HStack {
                                Text("Input channels are muted to protect privacy.")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("Grant Access") {
                                    Task {
                                        await audio.requestMicrophonePermission()
                                    }
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(6)
                }
                
                // 4. MIDI подсистема
                GroupBox(label: Label("MIDI Subsystem (E08.1 / E09)", systemImage: "pianokeys")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Connected Device:")
                                .font(.system(size: 11, weight: .bold))
                            Spacer()
                            Text(midi.connectedDeviceName)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(midi.connectedDeviceName.contains("No") ? .gray : .cyan)
                        }
                        
                        if let lastCC = midi.lastReceivedCC {
                            HStack {
                                Text("Last Event:")
                                    .font(.system(size: 11, weight: .bold))
                                Spacer()
                                Text("Ch \(lastCC.channel) | CC #\(lastCC.cc) = \(lastCC.value)")
                                    .font(.system(size: 11, design: .monospaced))
                            }
                        }
                    }
                    .padding(6)
                }
                
                // 5. Журнал ошибок и событий
                GroupBox(label: Label("Diagnostic Event Log (E08.7)", systemImage: "list.bullet.rectangle")) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let lastRoute = audio.diagnosticsReport.lastRouteEvent {
                            Text("Last Route Event: \(lastRoute)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        if audio.diagnosticsReport.recentErrors.isEmpty {
                            Text("No recent errors detected. Engine operating normally.")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(audio.diagnosticsReport.recentErrors, id: \.self) { errorStr in
                                HStack(alignment: .top, spacing: 4) {
                                    Text("⚠️")
                                        .font(.system(size: 10))
                                    Text(errorStr)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.red)
                                }
                            }
                            
                            Button("Clear Errors") {
                                audio.diagnosticsReport.recentErrors.removeAll()
                            }
                            .controlSize(.mini)
                            .padding(.top, 4)
                        }
                    }
                    .padding(6)
                }
            }
            .padding(14)
        }
    }
    
    private var stateColor: Color {
        switch audio.engineLifecycleState {
        case .running:
            return .green
        case .ready:
            return .orange
        case .degraded:
            return .yellow
        case .starting:
            return .blue
        case .stopped:
            return .gray
        case .failed:
            return .red
        }
    }
    
    private var transportStateDescription: String {
        switch audio.state {
        case .stopped: return "stopped"
        case .loading(let url): return "loading (\(url.lastPathComponent))"
        case .ready(let url): return "ready (\(url.lastPathComponent))"
        case .playing: return "playing"
        case .paused: return "paused"
        case .ended: return "ended (EOF)"
        case .failed(let err): return "failed (\(err.localizedDescription))"
        }
    }
}
