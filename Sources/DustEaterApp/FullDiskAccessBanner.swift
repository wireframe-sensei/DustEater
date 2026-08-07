import SwiftUI
import AppKit

/// Shown when the scanner couldn't even open the chosen root directory —
/// almost always because DustEater lacks Full Disk Access, since it runs
/// unsandboxed specifically so it can read arbitrary user directories.
struct FullDiskAccessBanner: View {
    let path: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Full Disk Access Required")
                .font(.title2.bold())

            Text("DustEater needs Full Disk Access to read “\(path)”. Grant it in System Settings, then choose the folder again.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)

            Button("Open System Settings…") {
                openFullDiskAccessSettings()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
