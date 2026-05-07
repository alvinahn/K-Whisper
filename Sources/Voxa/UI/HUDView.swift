import SwiftUI

struct HUDView: View {
    @ObservedObject var model: HUDViewModel

    var body: some View {
        HStack(spacing: 12) {
            indicator
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if case .recording = model.phase {
                Waveform(level: model.level)
                    .frame(width: 60, height: 28)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(strokeColor, lineWidth: 1.2)
                )
        )
        .frame(width: 320, height: 56)
    }

    private var strokeColor: Color {
        switch model.phase {
        case .recording: return .red.opacity(0.5)
        case .error: return .yellow
        default: return .white.opacity(0.08)
        }
    }

    private var title: String {
        switch model.phase {
        case .idle: return "Voxa"
        case .recording: return "Listening… \(formattedElapsed)"
        case .transcribing: return "Transcribing…"
        case .processing(let m): return "Processing (\(m))…"
        case .delivered: return "✓ Inserted"
        case .error(let m): return m
        }
    }

    private var subtitle: String {
        switch model.phase {
        case .recording:
            return model.level > 0.02
                ? "\(model.modeName) · Esc to cancel"
                : "\(model.modeName) · (no signal — speak up?)"
        case .processing:
            return model.language.isEmpty ? model.modeName : "\(model.modeName) · \(model.language.uppercased())"
        case .transcribing: return model.modeName
        case .error: return "See Console.app filter im.navio.voxa for detail"
        default: return model.modeName
        }
    }

    @ViewBuilder
    private var indicator: some View {
        switch model.phase {
        case .recording:
            ZStack {
                Circle().fill(.red.opacity(0.35))
                    .frame(width: 22, height: 22)
                    .scaleEffect(1 + CGFloat(model.level) * 1.6)
                    .animation(.easeOut(duration: 0.12), value: model.level)
                Circle().fill(.red).frame(width: 10, height: 10)
            }
        case .transcribing, .processing:
            ProgressView().controlSize(.small)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow).font(.title3)
        case .delivered:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
        case .idle:
            Image(systemName: "mic.fill").foregroundStyle(.secondary)
        }
    }

    private var formattedElapsed: String {
        let total = Int(model.elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Eight-bar voice-activity meter that animates from a center axis.
private struct Waveform: View {
    let level: Float

    private let barCount = 8
    private let multipliers: [CGFloat] = [0.4, 0.7, 1.0, 1.3, 1.3, 1.0, 0.7, 0.4]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(barColor(i))
                        .frame(
                            width: 3,
                            height: max(3, geo.size.height * heightFactor(i))
                        )
                        .animation(.easeOut(duration: 0.08), value: level)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func heightFactor(_ i: Int) -> CGFloat {
        // Use signal level + a small idle pulse so user sees life even with quiet audio.
        let base: CGFloat = 0.2
        let signal = CGFloat(level) * multipliers[i] * 1.2
        return min(1.0, base + signal)
    }

    private func barColor(_ i: Int) -> Color {
        let intensity = min(1.0, CGFloat(level) * multipliers[i] * 2)
        return Color(red: 1.0, green: 0.3 + 0.5 * (1 - intensity), blue: 0.3 + 0.5 * (1 - intensity))
    }
}
