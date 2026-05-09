import SwiftUI

@main
struct IconChangerApp: App {
    @StateObject private var model = IconChangerModel()

    var body: some Scene {
        WindowGroup("Icon Changer") {
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
