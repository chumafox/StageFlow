import SwiftUI

public struct VUMeterView: View {
    public var level: Float // 0.0 ... 1.0
    public var isClipping: Bool = false
    private let ledCount: Int = 14
    
    public init(level: Float, isClipping: Bool = false) {
        self.level = level
        self.isClipping = isClipping
    }
    
    public var body: some View {
        GeometryReader { geo in
            let ledHeight = max(2.0, (geo.size.height / CGFloat(ledCount)) - 2.5)
            
            VStack(spacing: 2.5) {
                ForEach((0..<ledCount).reversed(), id: \.self) { idx in
                    let threshold = Float(idx) / Float(ledCount)
                    let isTopClip = (idx == ledCount - 1) && isClipping
                    let isActive = isTopClip || (level >= threshold)
                    
                    RoundedRectangle(cornerRadius: 1)
                        .fill(isActive ? ledColor(threshold, isTopClip: isTopClip) : Color.white.opacity(0.06))
                        .frame(height: ledHeight)
                }
            }
        }
        .frame(width: 8)
        .padding(.horizontal, 3)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.8))
        .cornerRadius(4)
    }
    
    private func ledColor(_ threshold: Float, isTopClip: Bool = false) -> Color {
        if isTopClip || threshold > 0.82 {
            return .red
        } else if threshold > 0.60 {
            return .yellow
        } else {
            return .green
        }
    }
}
