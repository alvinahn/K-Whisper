import SwiftUI

struct MicLevelMeter: View {
    let level: Float
    let peak: Float
    let seconds: TimeInterval

    private let barCount = 22

    private var liveLevel: Double {
        let clamped = max(0, min(1, Double(level)))
        return pow(clamped, 0.72)
    }

    private var peakLevel: Double {
        let clamped = max(0, min(1, Double(peak)))
        return pow(clamped, 0.72)
    }

    private var activeBars: Int {
        max(0, min(barCount, Int((liveLevel * Double(barCount)).rounded(.up))))
    }

    private var peakBars: Int {
        max(0, min(barCount, Int((peakLevel * Double(barCount)).rounded(.up))))
    }

    private var quality: (String, Color) {
        switch peak {
        case ..<0.01:
            return ("신호 없음", .red)
        case ..<0.05:
            return ("작게 들림", .orange)
        case ..<0.82:
            return ("입력 양호", .green)
        default:
            return ("조금 큼", .yellow)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(quality.0, systemImage: quality.0 == "입력 양호" ? "checkmark.circle.fill" : "waveform")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(quality.1)
                Spacer()
                Text("피크 \(String(format: "%.2f", peak))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1fs", seconds))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(fillColor(for: index).opacity(opacity(for: index)))
                        .frame(width: 7, height: height(for: index))
                        .overlay(alignment: .top) {
                            if index == max(0, peakBars - 1), peak > 0.01 {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.9))
                                    .frame(width: 7, height: 2)
                                    .offset(y: -4)
                            }
                        }
                        .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.78), value: activeBars)
                }
            }
            .frame(height: 34, alignment: .bottom)
            .padding(.horizontal, 2)
            .accessibilityLabel("마이크 입력 레벨")
            .accessibilityValue("\(quality.0), 현재 \(String(format: "%.2f", level)), 피크 \(String(format: "%.2f", peak))")
        }
        .padding(.top, 2)
    }

    private func height(for index: Int) -> CGFloat {
        let wave = sin(Double(index) * 0.68) * 4.0
        let base = 11.0 + wave + Double(index % 4) * 2.0
        let boosted = Double(index) / Double(max(1, barCount - 1)) * 10.0
        return CGFloat(base + boosted)
    }

    private func opacity(for index: Int) -> Double {
        if index < activeBars { return 1.0 }
        if index < peakBars { return 0.38 }
        return 0.15
    }

    private func fillColor(for index: Int) -> Color {
        let ratio = Double(index + 1) / Double(barCount)
        switch ratio {
        case ..<0.66:
            return .green
        case ..<0.86:
            return .yellow
        default:
            return .red
        }
    }
}
