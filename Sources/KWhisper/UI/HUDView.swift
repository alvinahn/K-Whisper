import SwiftUI

struct HUDView: View {
    @ObservedObject var model: HUDViewModel

    var body: some View {
        HStack(spacing: 12) {
            indicator
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(textLineLimit)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(textLineLimit)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 6)
            if showsWaveform {
                ParticleWaveform(level: model.level, accentColor: waveformAccent)
                    .frame(width: 120, height: 32)
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
        // Clip everything to the pill so the recording indicator's halo
        // and the particles can't bleed past the rounded corners.
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(width: pillWidth, height: pillHeight)
    }

    /// Wider pill + 2-line text for errors so users can actually read them.
    private var pillWidth: CGFloat {
        if case .error = model.phase { return 420 }
        return 320
    }
    private var pillHeight: CGFloat {
        if case .error = model.phase { return 70 }
        return 56
    }
    private var textLineLimit: Int {
        if case .error = model.phase { return 2 }
        return 1
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
        case .idle: return "K-Whisper"
        case .recording: return "듣는 중… \(formattedElapsed)"
        case .transcribing: return "인식 중…"
        case .processing(let m): return "처리 중 (\(m))…"
        case .delivered: return "✓ 입력 완료"
        case .error(let m, _): return m
        }
    }

    private var subtitle: String {
        switch model.phase {
        case .recording:
            let exitHint: String = (model.recordingTrigger == .hold)
                ? "키를 놓으면 종료 · Esc 취소"
                : "다시 누르면 종료 · Esc 취소"
            return model.level > 0.02
                ? "\(model.modeName) · \(exitHint)"
                : "\(model.modeName) · 신호 약함"
        case .processing:
            let langPart = model.language.isEmpty ? model.modeName : "\(model.modeName) · \(model.language.uppercased())"
            return "\(langPart) · Esc로 취소"
        case .transcribing: return "\(model.modeName) · Esc로 취소"
        case .error(_, let hint): return hint ?? "Console.app에서 로그 확인"
        default: return model.modeName
        }
    }

    @ViewBuilder
    private var indicator: some View {
        switch model.phase {
        case .recording:
            // Halo scale capped at 1.35× so it can't overflow the pill rounded corner.
            ZStack {
                Circle()
                    .fill(.red.opacity(0.35))
                    .scaleEffect(min(1.35, 1 + CGFloat(model.level) * 0.5))
                    .animation(.easeOut(duration: 0.12), value: model.level)
                Circle().fill(.red).frame(width: 10, height: 10)
            }
            .frame(width: 22, height: 22)
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

    /// Show the waveform whenever there's "active work" — recording or post-processing.
    private var showsWaveform: Bool {
        switch model.phase {
        case .recording, .transcribing, .processing: return true
        default: return false
        }
    }

    /// Recording = hot red; processing = cool indigo. Conveys phase via color.
    private var waveformAccent: Color {
        switch model.phase {
        case .recording: return .red
        case .transcribing, .processing: return Color(red: 0.55, green: 0.45, blue: 1.0)
        default: return .secondary
        }
    }
}

// MARK: - Particle waveform (Design 4 port)

/// Floating particle field that responds to voice level. Particles drift across the
/// waveform area, fade in/out, and occasionally connect with constellation lines.
/// Powered by SwiftUI Canvas + TimelineView (.animation) — re-renders ~60 fps.
private struct ParticleWaveform: View {
    let level: Float
    let accentColor: Color
    @State private var system = ParticleSystem()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            Canvas(rendersAsynchronously: false) { ctx, size in
                system.advance(level: level, size: size, now: context.date)
                system.render(in: ctx, size: size, accent: accentColor)
            }
        }
    }
}

private final class ParticleSystem {
    struct Particle {
        var x: CGFloat
        var y: CGFloat
        var vx: CGFloat
        var vy: CGFloat
        var radius: CGFloat
        var life: TimeInterval
        var maxLife: TimeInterval
        var alpha: CGFloat
        var jitter: CGFloat
        var jitterSpeed: CGFloat
    }

    private var particles: [Particle] = []
    private var smoothLevel: CGFloat = 0
    private var spawnAccum: CGFloat = 0
    private var lastTime: Date?
    private let maxParticles = 36
    private var didSeed = false

    func advance(level: Float, size: CGSize, now: Date) {
        guard size.width > 0, size.height > 0 else { return }
        let last = lastTime ?? now
        let dt = min(0.05, now.timeIntervalSince(last))
        lastTime = now

        let target = CGFloat(min(max(level, 0), 1))
        smoothLevel += (target - smoothLevel) * (1 - CGFloat(exp(-dt * 8)))
        let lvl = smoothLevel

        if !didSeed {
            for _ in 0..<6 { spawn(in: size, seed: true) }
            didSeed = true
        }

        // Spawn rate: ~3/s at idle, ~22/s at full level
        let rate = 3.0 + Double(lvl) * 19.0
        spawnAccum += CGFloat(rate * dt)
        while spawnAccum >= 1, particles.count < maxParticles {
            spawnAccum -= 1
            spawn(in: size, seed: false)
        }

        // Update positions + cull
        let cy = size.height / 2
        let maxOff = size.height * 0.42
        for i in particles.indices {
            particles[i].life += dt
            particles[i].jitter += particles[i].jitterSpeed * CGFloat(dt)
            let wobble = sin(particles[i].jitter) * (0.4 + lvl * 1.6)
            particles[i].x += particles[i].vx * CGFloat(dt)
            particles[i].y += (particles[i].vy + wobble * 6) * CGFloat(dt)
            particles[i].y = max(cy - maxOff, min(cy + maxOff, particles[i].y))
        }
        particles.removeAll { p in
            (p.life / p.maxLife) >= 1 || p.x < -8 || p.x > size.width + 8
        }
    }

    private func spawn(in size: CGSize, seed: Bool) {
        let dir: CGFloat = Bool.random() ? 1 : -1
        let lvl = smoothLevel
        let speed = CGFloat.random(in: 8...26) + lvl * CGFloat.random(in: 30...70)
        let lifetime = TimeInterval.random(in: 1.6...3.6)
        let x: CGFloat = seed
            ? CGFloat.random(in: 0...size.width)
            : (dir > 0 ? -4 : size.width + 4)
        let yOffset = CGFloat.random(in: -size.height * 0.36 ... size.height * 0.36)
        let radius = CGFloat.random(in: 0.8...1.6) + lvl * CGFloat.random(in: 0.6...2.0)
        let baseAlpha = CGFloat.random(in: 0.35...0.9)

        particles.append(Particle(
            x: x,
            y: size.height / 2 + yOffset,
            vx: dir * speed,
            vy: CGFloat.random(in: -4...4) * (0.3 + lvl),
            radius: radius,
            life: 0,
            maxLife: lifetime,
            alpha: baseAlpha,
            jitter: CGFloat.random(in: 0...(2 * .pi)),
            jitterSpeed: CGFloat.random(in: 1.5...3.5)
        ))
    }

    func render(in ctx: GraphicsContext, size: CGSize, accent: Color) {
        let lvl = smoothLevel

        // Constellation lines — cheap O(n²) but n ≤ 36
        if lvl > 0.05 && particles.count > 1 {
            let linkDist = 22 + lvl * 18
            let linkDist2 = linkDist * linkDist
            for i in 0..<particles.count {
                let a = particles[i]
                for j in (i + 1)..<particles.count {
                    let b = particles[j]
                    let dx = a.x - b.x
                    let dy = a.y - b.y
                    let d2 = dx * dx + dy * dy
                    if d2 < linkDist2 {
                        let closeness = 1 - sqrt(d2) / linkDist
                        let alpha = closeness * 0.35 * (0.2 + lvl)
                        var path = Path()
                        path.move(to: CGPoint(x: a.x, y: a.y))
                        path.addLine(to: CGPoint(x: b.x, y: b.y))
                        ctx.stroke(path, with: .color(accent.opacity(alpha)), lineWidth: 0.6)
                    }
                }
            }
        }

        for p in particles {
            let t = p.life / p.maxLife
            // Lifecycle envelope: fade in 20%, plateau, fade out last 30%
            let env: CGFloat
            if t < 0.2 { env = CGFloat(t / 0.2) }
            else if t > 0.7 { env = CGFloat(1 - (t - 0.7) / 0.3) }
            else { env = 1 }
            // Edge fade so particles don't pop in/out at the borders
            let edgeFade = min(1, min(p.x / 14, (size.width - p.x) / 14))
            let alpha = p.alpha * env * max(0, edgeFade) * (0.45 + lvl * 0.55)
            if alpha <= 0.01 { continue }

            // Soft glow ring
            let glowR = p.radius * 2.4
            let glowRect = CGRect(x: p.x - glowR, y: p.y - glowR, width: glowR * 2, height: glowR * 2)
            ctx.fill(Path(ellipseIn: glowRect), with: .color(accent.opacity(alpha * 0.25)))

            // Core dot
            let coreRect = CGRect(x: p.x - p.radius, y: p.y - p.radius, width: p.radius * 2, height: p.radius * 2)
            ctx.fill(Path(ellipseIn: coreRect), with: .color(accent.opacity(alpha)))
        }
    }
}
