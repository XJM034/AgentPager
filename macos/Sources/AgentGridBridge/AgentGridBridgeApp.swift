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
        MenuBarExtra("AgentPager", systemImage: "square.grid.3x3.fill") {
            BridgeMenuView(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            BridgeSettingsView(model: model)
        }
        .defaultSize(width: 680, height: 520)
        .windowResizability(.contentMinSize)
    }
}
