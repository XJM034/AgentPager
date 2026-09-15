import AgentGridCore
import SwiftUI

/// Mac 常驻状态图标使用静态帧；仅在状态变化时重新绘制。
struct PixelCoreView: View {
    let lifecycle: AgentLifecycle
    let activity: AgentActivity?
    let compact: Bool

    init(
        lifecycle: AgentLifecycle,
        activity: AgentActivity?,
        compact: Bool = true
    ) {
        self.lifecycle = lifecycle
        self.activity = activity
        self.compact = compact
    }

    var body: some View {
        let samples = PixelMotion.sample(
            lifecycle: lifecycle,
            activity: activity,
            elapsed: PixelMotion.reducedMotionElapsed(lifecycle: lifecycle)
        )
        let color = Color(pixelHex: PixelPalette.hex(lifecycle: lifecycle, activity: activity))
        Canvas { graphics, size in
            let side = min(size.width, size.height) * (compact ? 0.68 : 0.62)
            let step = side / 3
            let cell = step * 0.58
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for sample in samples {
                let row = Double(sample.index / 3 - 1)
                let column = Double(sample.index % 3 - 1)
                let cellSide = cell * sample.scale
                let rect = CGRect(
                    x: center.x + (column + sample.offsetX) * step - cellSide / 2,
                    y: center.y + (row + sample.offsetY) * step - cellSide / 2,
                    width: cellSide,
                    height: cellSide
                )
                graphics.fill(
                    Path(rect),
                    with: .color(color.opacity(0.07 + sample.intensity * 0.93))
                )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("任务状态 \(lifecycle.rawValue)")
    }
}
