import SwiftUI

public struct VerticalFader: View {
    public let title: String
    @Binding public var value: Float
    public var peak: Float = 0.0
    public var isClipping: Bool = false
    public var tintColor: Color = .blue
    public var isMaster: Bool = false
    
    public init(title: String, value: Binding<Float>, peak: Float = 0.0, isClipping: Bool = false, tintColor: Color = .blue, isMaster: Bool = false) {
        self.title = title
        self._value = value
        self.peak = peak
        self.isClipping = isClipping
        self.tintColor = tintColor
        self.isMaster = isMaster
    }
    
    public var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(isMaster ? tintColor : .primary)
                .lineLimit(1)
            
            HStack(spacing: 6) {
                // Fader Slider
                ZStack {
                    Slider(value: $value, in: 0.0...1.0)
                        .tint(tintColor)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 110, height: 28)
                }
                .frame(width: 28, height: 110)
                
                // Segments VU meter
                VUMeterView(level: peak, isClipping: isClipping)
                    .frame(height: 110)
            }
            
            Text(String(format: "%.1f", value))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .frame(width: 60)
    }
}

public struct MicStripCard: View {
    @ObservedObject public var mic: MicChannelStrip
    public let title: String
    
    public init(mic: MicChannelStrip, title: String) {
        self.mic = mic
        self.title = title
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.white)
                Spacer()
                Button(mic.isMuted ? "MUTED" : "MUTE") {
                    mic.isMuted.toggle()
                }
                .buttonStyle(.borderedProminent)
                .tint(mic.isMuted ? .red : .gray.opacity(0.5))
                .controlSize(.mini)
                
                Button("SOLO") {
                    mic.isSolo.toggle()
                }
                .buttonStyle(.borderedProminent)
                .tint(mic.isSolo ? .yellow : .gray.opacity(0.5))
                .foregroundColor(mic.isSolo ? .black : .white)
                .controlSize(.mini)
            }
            
            HStack(spacing: 12) {
                VerticalFader(title: "FOH Out", value: $mic.fohVolume, peak: mic.peakLevel, isClipping: mic.isClipping, tintColor: .blue)
                VerticalFader(title: "In-Ear", value: $mic.iemVolume, peak: mic.peakLevel, isClipping: mic.isClipping, tintColor: .purple)
                
                VStack(spacing: 6) {
                    Text("DSP FX")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        Toggle("LowCut", isOn: $mic.lowCutEnabled)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 8))
                        Toggle("Comp", isOn: $mic.compressorEnabled)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 8))
                    }
                    
                    VStack(spacing: 2) {
                        Text("REV SEND")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.orange)
                        Slider(value: $mic.reverbSend, in: 0.0...1.0)
                            .tint(.orange)
                            .frame(width: 65)
                    }
                    
                    VStack(spacing: 2) {
                        Text("PRESENCE")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.cyan)
                        Slider(value: $mic.midGain, in: -6.0...6.0)
                            .tint(.cyan)
                            .frame(width: 65)
                    }
                }
                .frame(width: 80)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: NSColor.controlBackgroundColor).opacity(0.3)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}
