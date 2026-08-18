import SwiftUI
import AppKit
import DustEaterCore

/// Step 2 of the welcome flow, and also reused standalone (in a sheet) from
/// Cleanup's limited-access card - "Grant Access" there returns to this
/// exact same step rather than a simplified re-derivation of it. Owns its
/// own polling so both call sites get "access is detected, never relaunched"
/// for free: SwiftUI cancels `.task` automatically when this view leaves the
/// hierarchy (the welcome flow advancing to step 3, or the sheet being
/// dismissed), which is what "stop polling when it leaves" means in practice
/// - no explicit teardown call needed.
struct FullDiskAccessStepView: View {
    /// Called by "Continue without it" - the welcome flow jumps to step 3;
    /// the standalone sheet dismisses itself. Deliberately the caller's
    /// choice, not this view's: this view only owns the access-detection
    /// state, not what "leaving" means in either context.
    let onSkip: () -> Void

    private enum AccessState: Equatable { case idle, waiting, granted }
    @State private var accessState: AccessState = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Give DustEater Full Disk Access")
                    .font(.system(size: 26, weight: .bold))
                Text("macOS hides system caches and sandboxed app data from every app by default. Without access DustEater still scans and still reports real totals - it just tells you which locations it could not read.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                diagramColumn(number: 1, instruction: "In Privacy & Security, choose Full Disk Access.") {
                    privacyListMockup
                }
                diagramColumn(number: 2, instruction: "Find DustEater in the list.") {
                    appRowMockup
                }
                diagramColumn(number: 3, instruction: "Turn its switch on.") {
                    switchMockup
                }
            }

            statusRow

            if accessState != .granted {
                HStack(spacing: 12) {
                    Button(action: openFullDiskAccessSettings) {
                        Text("Open Full Disk Access")
                            .font(.control)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Continue without it", action: onSkip)
                        .font(.control)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
        }
        // Keyed on `accessState` itself: tapping "Open Full Disk Access"
        // moves it to `.waiting`, which starts a fresh poll loop; the loop
        // exits on its own the moment access is granted, and SwiftUI cancels
        // it outright the moment this view disappears. Never prints the
        // usual "quit and reopen" instruction - the whole point of polling
        // is that the user never needs to see that.
        .task(id: accessState) {
            guard accessState == .waiting else { return }
            while !Task.isCancelled {
                if AccessProbe.hasFullDiskAccess() {
                    accessState = .granted
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func openFullDiskAccessSettings() {
        accessState = .waiting
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch accessState {
        case .idle:
            EmptyView()
        case .waiting:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for access. Leave DustEater open - it notices the moment you grant it.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        case .granted:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(nsColor: .systemGreen))
                Text("Access granted. No relaunch needed - DustEater picked it up on its own.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: .systemGreen))
            }
        }
    }

    private func diagramColumn<Content: View>(
        number: Int,
        instruction: String,
        @ViewBuilder mockup: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.accentColor, in: Circle())
            Text(instruction)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            mockup()
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(12)
        // A fixed `height`, not `minHeight`: `WelcomeView`'s centering trick
        // (`GeometryReader` + `.frame(minHeight:)` on the scroll content, so
        // the column can center within a tall window instead of pinning to
        // the top) proposes up to the *full window height* down through
        // this view tree. `Spacer(minLength: 8)` above is greedy by design -
        // it accepts whatever height it's offered - so a bare `minHeight`
        // here let the column balloon to fill that entire proposal instead
        // of staying card-sized. A fixed height caps it regardless of what
        // its ancestors propose.
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 140)
        .background(Color.opaqueTertiaryFill, in: RoundedRectangle(cornerRadius: 12))
        .hairlineRing(cornerRadius: 12)
    }

    private var privacyListMockup: some View {
        VStack(spacing: 3) {
            mockRow(filled: false)
            mockRow(filled: true)
            mockRow(filled: false)
        }
    }

    private func mockRow(filled: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(filled ? Color.accentColor : Color(nsColor: .quaternaryLabelColor))
            .frame(height: 10)
            .frame(maxWidth: .infinity)
    }

    private var appRowMockup: some View {
        HStack(spacing: 6) {
            appIconView
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text("DustEater")
                .font(.system(size: 11))
        }
    }

    @ViewBuilder
    private var appIconView: some View {
        if let icon = NSApplication.shared.applicationIconImage {
            Image(nsImage: icon).resizable()
        } else {
            RoundedRectangle(cornerRadius: 4).fill(Color.accentColor)
        }
    }

    private var switchMockup: some View {
        Toggle("", isOn: .constant(true))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .disabled(true)
    }
}
