import AgentGridCore
import SwiftUI

struct PixelCoreView: View {
    let lifecycle: AgentLifecycle
    let activity: AgentActivity?
    let compact: Bool

    @State private var phase = false

    private let gridSize = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Canvas { graphics, size in
                draw(in: &graphics, size: size, time: time)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("任务状态 \(lifecycle.rawValue)")
    }

    private var frameInterval: TimeInterval {
        switch lifecycle {
        case .idle, .offline: 1 / 12
        case .succeeded, .failed, .interrupted: 1 / 60
        default: 1 / 30
        }
    }

    private func draw(in graphics: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let gap = compact ? 2.0 : 4.0
        let side = min(size.width, size.height)
        let cell = (side - gap * Double(gridSize - 1)) / Double(gridSize)
        let originX = (size.width - side) / 2
        let originY = (size.height - side) / 2
        let pulse = 0.76 + sin(time * speed) * 0.18

        for row in 0..<gridSize {
            for column in 0..<gridSize {
                let distance = abs(row - 2) + abs(column - 2)
                let active = pixelIsActive(row: row, column: column, time: time)
                let alpha = active ? pulse : 0.12
                let rect = CGRect(
                    x: originX + Double(column) * (cell + gap),
                    y: originY + Double(row) * (cell + gap),
                    width: cell,
                    height: cell
                )

                let color = color(distance: distance)
                let glow = rect.insetBy(dx: -cell * 0.28, dy: -cell * 0.28)
                graphics.fill(
                    Path(glow),
                    with: .color(color.opacity(alpha * 0.12))
                )
                graphics.fill(
                    Path(rect),
                    with: .color(color.opacity(alpha))
                )
            }
        }
    }

    private var speed: Double {
        switch lifecycle {
        case .waitingApproval, .waitingAnswer: 8
        case .failed: 12
        case .succeeded: 7
        case .running: 5
        default: 2
        }
    }

    private func pixelIsActive(row: Int, column: Int, time: TimeInterval) -> Bool {
        let tick = Int(time * speed)
        switch lifecycle {
        case .waitingApproval:
            return row == tick % gridSize || column == tick % gridSize
        case .waitingAnswer:
            return (row + column + tick) % 3 != 0
        case .failed:
            return row == column || row + column == gridSize - 1
        case .succeeded:
            return row >= 2 && column <= row
        case .running:
            return (row * gridSize + column + tick) % 4 != 0
        case .starting:
            return abs(row - 2) + abs(column - 2) <= tick % 5
        case .interrupted:
            return row == 2
        case .offline, .idle:
            return abs(row - 2) + abs(column - 2) <= 1
        }
    }

    private func color(distance: Int) -> Color {
        switch lifecycle {
        case .waitingApproval: Color(red: 1.00, green: 0.62, blue: 0.26)
        case .waitingAnswer: Color(red: 0.96, green: 0.79, blue: 0.36)
        case .failed: Color(red: 1.00, green: 0.38, blue: 0.44)
        case .succeeded: Color(red: 0.34, green: 0.84, blue: 0.55)
        case .interrupted: Color(red: 0.55, green: 0.58, blue: 0.65)
        case .offline: Color(red: 0.30, green: 0.33, blue: 0.39)
        default:
            [
                Color(red: 0.96, green: 0.45, blue: 0.36),
                Color(red: 0.69, green: 0.45, blue: 0.95),
                Color(red: 0.31, green: 0.55, blue: 0.98),
                Color(red: 0.25, green: 0.74, blue: 0.67),
            ][min(distance, 3)]
        }
    }
}

