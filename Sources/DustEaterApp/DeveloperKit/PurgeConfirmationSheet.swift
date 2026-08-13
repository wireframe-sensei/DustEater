import SwiftUI
import DustEaterCore

/// Progress for one item mid-purge, surfaced inside `PurgeConfirmationSheet`
/// while `DeveloperKitView.performPurge` runs - "Deleting DerivedData...
/// (3 of 7)" rather than a bare spinner, since a single target (DerivedData
/// especially) can take real wall-clock time to remove.
struct PurgeDeletionProgress {
    let completed: Int
    let total: Int
    let currentTitle: String
}

/// Destructive confirmation for a batch purge from the Developer Kit.
/// Modeled on `DuplicateCleanConfirmationSheet` (animated byte counter,
/// error panel accumulated rather than swallowed) but adds what neither
/// existing confirmation sheet needs: a per-safety-level breakdown, the
/// exact rebuild commands for everything `.rebuildable` in the selection, a
/// callout for any target whose owning app is currently running, and real
/// per-item progress instead of a bare spinner.
struct PurgeConfirmationSheet: View {
    let targets: [PurgeTarget]
    let totalBytesToReclaim: Int64
    let deletionProgress: PurgeDeletionProgress?
    @Binding var isDeleting: Bool
    @Binding var errorMessage: String?
    let onConfirm: (_ permanently: Bool) -> Void

    @State private var displayedBytes: Int64 = 0
    @Environment(\.dismiss) private var dismiss

    private var safeCount: Int { targets.filter { $0.safety == .safe }.count }
    private var rebuildableCount: Int { targets.filter { $0.safety == .rebuildable }.count }
    private var cautionCount: Int { targets.filter { $0.safety == .caution }.count }

    private var rebuildCommands: [String] {
        Set(targets.compactMap(\.definition.rebuildCommand)).sorted()
    }

    /// Targets whose owning app is running right now - shown so the user
    /// isn't surprised when `performPurge` skips them. Advisory only: the
    /// actual refusal happens per-item at delete time, since "running" can
    /// change in the window this sheet stays open.
    private var blockedTargets: [PurgeTarget] {
        targets.filter { target in
            guard let bundleID = target.definition.blockingAppBundleID else { return false }
            return FileOperations.isAppRunning(bundleIdentifier: bundleID)
        }
    }

    /// Moving 40 GB of DerivedData to the Trash frees zero bytes until
    /// emptied, and the Trash sits on the same volume - the entire point of
    /// this screen is freeing space now, so Delete Permanently is the
    /// prominent action by default. That flips the moment a `.caution`
    /// target is included: something that can destroy data with no
    /// regeneration path deserves the extra friction of Trash-by-default,
    /// same as every other destructive action in this app.
    private var cautionIncluded: Bool { cautionCount > 0 }

    var body: some View {
        VStack(spacing: 20) {
            header
            byteCounter

            if !blockedTargets.isEmpty {
                blockedCallout
            }

            breakdown

            if !rebuildCommands.isEmpty {
                rebuildCommandsList
            }

            if let deletionProgress {
                progressBanner(deletionProgress)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
                    .frame(maxWidth: .infinity)
            }

            Spacer()
            actionButtons
        }
        .padding(.horizontal, 20)
        .frame(minWidth: 480, minHeight: 460)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                displayedBytes = totalBytesToReclaim
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.red.opacity(0.7))
            Text("Purge Selected")
                .font(.headline)
            Text("Delete \(targets.count) item\(targets.count == 1 ? "" : "s")?")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    private var byteCounter: some View {
        VStack(spacing: 8) {
            Text("You'll recover")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(ByteFormatter.string(fromBytes: displayedBytes))
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var breakdown: some View {
        HStack(spacing: 16) {
            breakdownItem(count: safeCount, label: "Safe", tint: Color(nsColor: .systemGreen))
            breakdownItem(count: rebuildableCount, label: "Rebuildable", tint: Color(nsColor: .systemTeal))
            breakdownItem(count: cautionCount, label: "Caution", tint: Color(nsColor: .systemOrange))
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func breakdownItem(count: Int, label: String, tint: Color) -> some View {
        if count > 0 {
            VStack(spacing: 2) {
                Text("\(count)")
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var rebuildCommandsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Rebuild afterward with:")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(rebuildCommands, id: \.self) { command in
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var blockedCallout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Some Targets Will Be Skipped")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            Text("\(blockedTargets.map(\.definition.title).joined(separator: ", ")) - the owning app is currently running. Quit it and try again to include \(blockedTargets.count == 1 ? "this item" : "these items").")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progressBanner(_ progress: PurgeDeletionProgress) -> some View {
        VStack(spacing: 6) {
            ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1)))
            Text("Deleting \(progress.currentTitle)... (\(progress.completed) of \(progress.total))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .font(.control)
            .buttonStyle(.bordered)
            .disabled(isDeleting)

            Spacer()

            trashButton
            permanentButton
        }
        .padding(.bottom, 20)
    }

    // `.buttonStyle` takes a concrete generic `ButtonStyle`, so a ternary
    // between `.bordered` and `.borderedProminent` can't sit inline as one
    // modifier argument (their types differ) - split into two small
    // `@ViewBuilder` properties instead of reaching for a type-erasing
    // wrapper for what's really just "one of these two buttons is prominent."
    @ViewBuilder
    private var trashButton: some View {
        let label: some View = Group {
            if isDeleting && cautionIncluded {
                ProgressView().scaleEffect(0.8)
            } else {
                Label("Move to Trash", systemImage: "trash")
            }
        }
        if cautionIncluded {
            Button(action: { onConfirm(false) }) { label }
                .font(.control)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isDeleting)
        } else {
            Button(action: { onConfirm(false) }) { label }
                .font(.control)
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(isDeleting)
        }
    }

    @ViewBuilder
    private var permanentButton: some View {
        let label: some View = Group {
            if isDeleting && !cautionIncluded {
                ProgressView().scaleEffect(0.8)
            } else {
                Text("Delete Permanently")
            }
        }
        if cautionIncluded {
            Button(action: { onConfirm(true) }) { label }
                .font(.control)
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(isDeleting)
        } else {
            Button(action: { onConfirm(true) }) { label }
                .font(.control)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isDeleting)
        }
    }
}
