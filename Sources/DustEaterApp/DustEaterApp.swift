import SwiftUI
import AppKit

@main
struct DustEaterApp: App {
    // Plain reference types held via `@State` purely for stable identity
    // across `body` re-evaluations - same pattern `ContentView.coordinator`/
    // `treemapCache` already use. `monitoringSettings` is created here
    // (not inside `ContentView`) specifically so the same instance can be
    // passed into both the `WindowGroup` and the separate `Settings {}`
    // scene - two different windows that both need to see the other's
    // changes immediately. `statusItemController` lives here for a
    // stronger reason: it must outlive the main window closing, since the
    // entire point of a menu bar presence is working without a window open.
    @State private var monitoringSettings = MonitoringSettingsStore()
    @State private var statusItemController = StatusItemController()

    var body: some Scene {
        WindowGroup("DustEater") {
            ContentView(monitoringSettings: monitoringSettings, statusItemController: statusItemController)
                .frame(minWidth: 1000, minHeight: 600)
                .onAppear(perform: setDockIcon)
        }
        .defaultSize(width: 1200, height: 700)
        .windowToolbarStyle(.unified(showsTitle: true))

        Settings {
            SettingsView(monitoringSettings: monitoringSettings)
        }
    }

    /// A packaged release `.app` already gets its icon from
    /// `Packaging/Info.plist`'s `CFBundleIconFile` - this is a no-op there.
    /// It's for `swift run`, which launches a bare unbundled executable
    /// with no Info.plist at all, so without this the Dock would show the
    /// generic default icon during local development.
    ///
    /// The guard below is load-bearing, not a style choice: `Bundle.module`
    /// crashed every packaged release since v0.1.1 (`fatalError`, caught
    /// live in a v0.4.0 crash report). SwiftPM's generated accessor tries
    /// two paths - the resource bundle next to the running executable, then
    /// a fallback hardcoded to the *build machine's* absolute `.build`
    /// path. `release.yml` never copies `DustEater_DustEaterApp.bundle`
    /// into the assembled `.app` (only the executable and `AppIcon.icns`
    /// are), and the CI runner's `.build` directory is gone the moment the
    /// job ends - so on every real user install, both of `Bundle.module`'s
    /// candidates are missing and it hits `fatalError`. (This is also why
    /// testing this locally by simply running the built binary can lie:
    /// the fallback path happens to exist on whichever machine actually
    /// built it, masking the crash there alone.) Skip touching
    /// `Bundle.module` entirely once packaged - a real `.app` bundle URL
    /// ends in `.app`; a bare `swift run` executable's does not.
    private func setDockIcon() {
        guard Bundle.main.bundleURL.pathExtension != "app" else { return }
        guard let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return }
        NSApplication.shared.applicationIconImage = image
    }
}
