import SwiftUI
import DustEaterCore

/// The post-scan default screen: findings ranked by reclaimable bytes,
/// largest first, nothing pre-selected. See the design handoff's "Cleanup"
/// section for the exact copy and layout this implements.
struct CleanupView: View {
    let findings: [CleanupFinding]
    let selection: SelectionStore
    @Binding var expandedFindings: Set<CleanupFindingID>
    /// Set by the sidebar's Findings jump list to scroll to and expand a
    /// group; consumed and reset to `nil` once handled.
    @Binding var scrollToFindingID: CleanupFindingID?
    let onOpenAppManager: () -> Void
    let onOpenXcodeArchives: () -> Void
    let canUndo: Bool
    let onReviewShortcut: () -> Void
    let onUndoShortcut: () -> Void
    let onRescanShortcut: () -> Void
    /// Item 9: `false` when this scan ran without Full Disk Access - shows
    /// the limited-access card above the finding groups. Checked live
    /// (`AccessProbe.hasFullDiskAccess()`), not remembered from onboarding,
    /// so a user who granted access during onboarding and later revoked it
    /// (or vice versa) sees the card reflect reality on the next scan.
    let hasFullDiskAccess: Bool
    let onGrantAccess: () -> Void

    @State private var focusedItemID: String?
    @State private var quickLookItem: CleanupItem?

    private var totalReclaimable: Int64 {
        findings.reduce(0) { $0 + $1.reclaimableBytes }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if !hasFullDiskAccess {
                        LimitedAccessCard(totalReclaimable: totalReclaimable, onGrantAccess: onGrantAccess)
                    }
                    if findings.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 10) {
                            ForEach(findings) { finding in
                                FindingGroupView(
                                    finding: finding,
                                    selection: selection,
                                    isExpanded: expandedBinding(for: finding.id),
                                    focusedItemID: $focusedItemID,
                                    onQuickLook: { quickLookItem = $0 },
                                    onFooterAction: { handleFooterAction(for: finding.id) }
                                )
                                .id(finding.id)
                            }
                        }
                        keyboardHintStrip
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: scrollToFindingID) { _, newValue in
                guard let newValue else { return }
                jump(to: newValue, proxy: proxy)
            }
        }
        .sheet(item: $quickLookItem) { item in
            QuickLookPreviewPane(path: item.revealPath, onRunAgain: {})
                .frame(width: 480, height: 360)
        }
        .onKeyPress(.space) {
            guard let focusedItemID, let item = findings.flatMap(\.items).first(where: { $0.id == focusedItemID }) else {
                return .ignored
            }
            quickLookItem = item
            return .handled
        }
        .background {
            // Invisible buttons rather than a bare `.onKeyPress` for the
            // remaining shortcuts, so each carries its own `.disabled` state
            // (SwiftUI still ignores a disabled `.keyboardShortcut`) instead
            // of hand-rolling that check inside a key-press handler. Scoped
            // to zero size within their own group, not the whole screen -
            // hiding the outer view chain here would hide the real content.
            Group {
                Button("Review", action: onReviewShortcut)
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(selection.count == 0)
                Button("Undo", action: onUndoShortcut)
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!canUndo)
                Button("Rescan", action: onRescanShortcut)
                    .keyboardShortcut("r", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .hidden()
        }
    }

    private func expandedBinding(for id: CleanupFindingID) -> Binding<Bool> {
        Binding(
            get: { expandedFindings.contains(id) },
            set: { isOn in
                if isOn { expandedFindings.insert(id) } else { expandedFindings.remove(id) }
            }
        )
    }

    /// Expanding a collapsed group and scrolling to it in the same update is
    /// a silent no-op - the `List`/`ScrollView` hasn't rebuilt to
    /// materialize the row yet. Same fix `FileTreeListView.reveal(_:proxy:)`
    /// already uses: a `Task.yield()` then a short sleep, taken only when
    /// the target actually needed expanding.
    private func jump(to id: CleanupFindingID, proxy: ScrollViewProxy) {
        Task {
            let needsExpand = !expandedFindings.contains(id)
            if needsExpand {
                expandedFindings.insert(id)
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(50))
            }
            withAnimation { proxy.scrollTo(id, anchor: .top) }
            scrollToFindingID = nil
        }
    }

    private func handleFooterAction(for id: CleanupFindingID) {
        switch id {
        case .unusedApplications: onOpenAppManager()
        case .xcodeBuildArtifacts: onOpenXcodeArchives()
        default: break
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("RECLAIM UP TO")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.tertiary)
                Text(ByteFormatter.string(fromBytes: totalReclaimable))
                    .font(.system(size: 44, weight: .bold).monospacedDigit())
                Text("across \(findings.count) finding\(findings.count == 1 ? "" : "s"), largest first")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(nsColor: .systemGreen))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Never touched")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Documents, your Photos library, iCloud Drive files and anything in Time Machine backups are excluded from every scan.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: 330, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: CleanupMetrics.panelCardRadius))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Nothing to Clean Up")
                .font(.system(size: 15, weight: .semibold))
            Text("This scan didn't turn up any of the six things DustEater looks for.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var keyboardHintStrip: some View {
        Text("Space to preview  ·  ⌘⌫ to Trash  ·  ⌘Z to undo  ·  ⌘R to rescan")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
    }
}

/// Item 9: shown above the finding groups when this scan ran without Full
/// Disk Access. Per the design handoff, totals stay honest, not hedged -
/// the 44pt header total above this card is never qualified with "at
/// least" or an asterisk; this card states the gap once, in words, next to
/// exactly what was skipped.
private struct LimitedAccessCard: View {
    let totalReclaimable: Int64
    let onGrantAccess: () -> Void

    /// Fixed, not derived from the scan - these four locations are always
    /// what Full Disk Access unlocks, regardless of what this particular
    /// scan happened to find.
    private static let skippedLocations: [(path: String, reason: String)] = [
        ("/Library/Caches", "System-wide caches, usually the largest single finding"),
        ("~/Library/Containers", "Sandboxed app data - Mail, Messages, News"),
        ("~/Library/Group Containers", "Data shared between apps from one developer"),
        ("/private/var/folders", "Temporary files macOS keeps per session")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(nsColor: .systemOrange))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scanned without Full Disk Access")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Every figure above is real and measured. These four locations were skipped, so there is more to find than \(ByteFormatter.string(fromBytes: totalReclaimable)).")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button("Grant Access", action: onGrantAccess)
                    .font(.control)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(nsColor: .systemOrange))
            }

            VStack(spacing: 0) {
                ForEach(Array(Self.skippedLocations.enumerated()), id: \.offset) { index, location in
                    HStack {
                        Text(location.path)
                            .font(.system(size: 11).monospaced())
                        Spacer()
                        Text(location.reason)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                    if index != Self.skippedLocations.count - 1 {
                        Divider().opacity(0.2)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .systemOrange).opacity(0.10), in: RoundedRectangle(cornerRadius: CleanupMetrics.panelCardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: CleanupMetrics.panelCardRadius)
                .strokeBorder(Color(nsColor: .systemOrange).opacity(0.20), lineWidth: 1)
        )
    }
}
