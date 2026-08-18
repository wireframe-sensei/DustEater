import SwiftUI
import AppKit
import UserNotifications

struct SettingsView: View {
    let monitoringSettings: MonitoringSettingsStore

    @State private var protectedAppsStore = ProtectedAppsStore()
    @Environment(\.controlMetrics) private var metrics

    var protectedAppDetails: [(bundleIdentifier: String, displayName: String, icon: NSImage)] {
        return protectedAppsStore.protectedBundleIdentifiers.sorted().compactMap { bundleID in
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let displayName = appURL.deletingPathExtension().lastPathComponent
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                return (bundleID, displayName, icon)
            }
            return (bundleID, bundleID, NSImage())
        }
    }

    var body: some View {
        TabView {
            VStack(spacing: 20) {
                Text("Protected Apps")
                    .font(.headline)

                Text("Apps in this list cannot be uninstalled through App Manager.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                List {
                    ForEach(protectedAppDetails, id: \.bundleIdentifier) { app in
                        HStack(spacing: 12) {
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 16, height: 16)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.displayName)
                                    .font(.control)
                                Text(app.bundleIdentifier)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button(action: {
                                protectedAppsStore.unprotect(bundleIdentifier: app.bundleIdentifier)
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Remove from protected list")
                        }
                    }
                }
                .listStyle(.plain)

                Button(action: selectAndAddApp) {
                    Label("Add Protected App...", systemImage: "plus")
                }
                .font(.control)
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tabItem {
                Label("Protection", systemImage: "lock.shield")
            }

            MonitoringSettingsPane(settings: monitoringSettings)
                .tabItem {
                    Label("Monitoring", systemImage: "gauge.with.dots.needle.33percent")
                }
        }
        .frame(width: 520, height: 620)
    }

    private func selectAndAddApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Select App"

        if panel.runModal() == .OK, let url = panel.url {
            if let bundleID = Bundle(url: url)?.bundleIdentifier {
                protectedAppsStore.protect(bundleIdentifier: bundleID)
            }
        }
    }
}

#Preview {
    SettingsView(monitoringSettings: MonitoringSettingsStore())
}
