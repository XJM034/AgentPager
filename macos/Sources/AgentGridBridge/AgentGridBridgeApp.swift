import SwiftUI

@main
struct AgentGridBridgeApp: App {
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
            Label("AgentGrid", systemImage: "square.grid.3x3.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            BridgeSettingsView(model: model)
        }
        .defaultSize(width: 680, height: 520)
        .windowResizability(.contentMinSize)
    }
}
