import SwiftUI

@main
struct DustEaterApp: App {
    var body: some Scene {
        WindowGroup("DustEater") {
            ContentView()
                .frame(minWidth: 1000, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 700)
    }
}
