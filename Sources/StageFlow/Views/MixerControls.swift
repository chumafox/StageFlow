import SwiftUI

public struct VerticalFader: View {
    public let title: String
    @Binding public var value: Float
    public var peak: Float = 0.0
    public var tintColor: Color = .blue
    public var isMaster: Bool = false
    
    public init(title: String, value: Binding<Float>, peak: Float = 0.0, tintColor: Color = .blue, isMaster: Bool = false) {
        self.title = title
        self._value = value
        self.peak = peak
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
                VUMeterView(level: peak)
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
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.white)
                Spacer()
                Button(mic.isMuted ? "MUTED" : "LIVE") {
                    mic.isMuted.toggle()
                }
                .buttonStyle(.borderedProminent)
                .tint(mic.isMuted ? .red : .green.opacity(0.8))
                .controlSize(.mini)
            }
            
            HStack(spacing: 12) {
                VerticalFader(title: "FOH Out", value: $mic.fohVolume, peak: mic.peakLevel, tintColor: .blue)
                VerticalFader(title: "In-Ear", value: $mic.iemVolume, peak: mic.peakLevel, tintColor: .purple)
                
                VStack(spacing: 6) {
                    Text("DSP FX")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    Toggle("LowCut", isOn: $mic.lowCutEnabled)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 9))
                    
                    VStack(spacing: 2) {
                        Text("REV SEND")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.orange)
                        Slider(value: $mic.reverbSend, in: 0.0...1.0)
                            .tint(.orange)
                            .frame(width: 55)
                    }
                    
                    VStack(spacing: 2) {
                        Text("PRESENCE")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.cyan)
                        Slider(value: $mic.midGain, in: -6.0...6.0)
                            .tint(.cyan)
                            .frame(width: 55)
                    }
                }
                .frame(width: 65)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: NSColor.controlBackgroundColor).opacity(0.3)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}
