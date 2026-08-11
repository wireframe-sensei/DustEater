import SwiftUI
import AppKit

@main
struct DustEaterApp: App {
    var body: some Scene {
        WindowGroup("DustEater") {
            ContentView()
                .frame(minWidth: 1000, minHeight: 600)
                .onAppear(perform: setDockIcon)
        }
        .defaultSize(width: 1200, height: 700)
        .windowToolbarStyle(.unified(showsTitle: true))

        Settings {
            SettingsView()
        }
    }

    /// A packaged release `.app` already gets its icon from
    /// `Packaging/Info.plist`'s `CFBundleIconFile` - this is a no-op there.
    /// It's for `swift run`, which launches a bare unbundled executable
    /// with no Info.plist at all, so without this the Dock would show the
    /// generic default icon during local development.
    private func setDockIcon() {
        guard let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return }
        NSApplication.shared.applicationIconImage = image
    }
}
