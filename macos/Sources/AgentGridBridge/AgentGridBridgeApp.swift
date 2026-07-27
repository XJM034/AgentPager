import SwiftUI

@main
struct AgentPagerBridgeApp: App {
    @State private var model: BridgeModel

    init() {
        PixelFontRegistry.register()
        let model = BridgeModel()
        _model = State(initialValue: model)
        model.start()
    }

    var body: some Scene {
        MenuBarExtra {
            BridgeMenuView(model: model)
        } label: {
            AgentPagerMenuBarIcon()
                .accessibilityLabel("AgentPager")
        }
        .menuBarExtraStyle(.window)

        Settings {
            BridgeSettingsView(model: model)
        }
        .defaultSize(width: 680, height: 520)
        .windowResizability(.contentMinSize)
    }
}

private struct AgentPagerMenuBarIcon: View {
    private let 可见格点 = [
        (列: 0, 行: 0),
        (列: 1, 行: 0),
        (列: 2, 行: 0),
        (列: 0, 行: 1),
        (列: 2, 行: 1),
        (列: 0, 行: 2),
        (列: 1, 行: 2),
        (列: 2, 行: 2),
    ]

    var body: some View {
        Canvas { context, _ in
            var 格点路径 = Path()
            for 格点 in 可见格点 {
                格点路径.addRect(
                    CGRect(
                        x: CGFloat(格点.列 * 4),
                        y: CGFloat(格点.行 * 4 + 6),
                        width: 3,
                        height: 3
                    )
                )
            }
            context.fill(格点路径, with: .foreground)

            var 信号路径 = Path()
            信号路径.move(to: CGPoint(x: 11.5, y: 4.5))
            信号路径.addLine(to: CGPoint(x: 14, y: 4.5))
            信号路径.addLine(to: CGPoint(x: 14, y: 7))
            信号路径.move(to: CGPoint(x: 11.5, y: 1.5))
            信号路径.addLine(to: CGPoint(x: 17, y: 1.5))
            信号路径.addLine(to: CGPoint(x: 17, y: 7))
            context.stroke(
                信号路径,
                with: .foreground,
                style: StrokeStyle(
                    lineWidth: 1.5,
                    lineCap: .butt,
                    lineJoin: .miter
                )
            )
        }
        .frame(width: 18, height: 18)
    }
}
