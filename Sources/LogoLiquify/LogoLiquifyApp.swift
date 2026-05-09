import SwiftUI

@main
struct LogoLiquifyApp: App {
    @StateObject private var model = LogoLiquifyModel()

    var body: some Scene {
        WindowGroup("Logo Liquify") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 660, minHeight: 540)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
