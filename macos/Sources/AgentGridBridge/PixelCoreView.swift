import AgentGridCore
import SwiftUI

struct PixelCoreView: View {
    let lifecycle: AgentLifecycle
    let activity: AgentActivity?
    let changedAt: Date
    let compact: Bool

    init(
        lifecycle: AgentLifecycle,
        activity: AgentActivity?,
        changedAt: Date,
        compact: Bool = true
    ) {
        self.lifecycle = lifecycle
        self.activity = activity
        self.changedAt = changedAt
        self.compact = compact
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval, paused: false)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(changedAt))
            Canvas(rendersAsynchronously: false) { graphics, size in
                draw(
                    in: &graphics,
                    size: size,
                    elapsed: elapsed
                )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("任务状态 \(lifecycle.rawValue)")
    }

    private var frameInterval: TimeInterval {
        switch lifecycle {
        case .idle, .offline:
            1 / 30
        case .succeeded, .failed, .interrupted:
            1 / 30
        default:
            1 / 60
        }
    }

    private func draw(
        in graphics: inout GraphicsContext,
        size: CGSize,
        elapsed: TimeInterval
    ) {
        let samples = PixelMotion.sample(
            lifecycle: lifecycle,
            activity: activity,
            elapsed: elapsed
        )
        let color = Color(pixelHex: PixelPalette.hex(
            lifecycle: lifecycle,
            activity: activity
        ))
        let burst = PixelMotion.burst(
            lifecycle: lifecycle,
            elapsed: elapsed
        )
        let side = min(size.width, size.height) * (compact ? 0.68 : 0.62)
        let step = side / 3
        let cell = step * 0.58
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        for sample in samples {
            let row = Double(sample.index / 3 - 1)
            let column = Double(sample.index % 3 - 1)
            let point = CGPoint(
                x: center.x + (column + sample.offsetX) * step,
                y: center.y + (row + sample.offsetY) * step
            )
            let cellSide = cell * sample.scale
            let rect = CGRect(
                x: point.x - cellSide / 2,
                y: point.y - cellSide / 2,
                width: cellSide,
                height: cellSide
            )

            // 每个亮格分别绘制外、中、内三层 Bloom，位移时光晕跟随该格。
            for glow in PixelMotion.glowLayers(
                intensity: sample.intensity,
                burst: burst
            ).reversed() where glow.opacity > 0 {
                graphics.drawLayer { layer in
                    layer.blendMode = .screen
                    layer.addFilter(.blur(radius: glow.blurRadius))
                    layer.fill(
                        Path(rect),
                        with: .color(color.opacity(glow.opacity))
                    )
                }
            }

            graphics.fill(
                Path(rect),
                with: .color(color.opacity(0.10))
            )
            graphics.fill(
                Path(rect),
                with: .color(color.opacity(0.22 + sample.intensity * 0.78))
            )
        }
    }
}
