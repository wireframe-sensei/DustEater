import SwiftUI
import DustEaterCore

/// One finding's card on the Cleanup screen: a header with a group checkbox,
/// disclosure, name, safety pill and reason, then - once expanded - one row
/// per item with a checkbox (or, for `.reportOnly`, a lock), path, note,
/// size, and Quick Look / Reveal in Finder buttons.
struct FindingGroupView: View {
    let finding: CleanupFinding
    let selection: SelectionStore
    @Binding var isExpanded: Bool
    @Binding var focusedItemID: String?
    let onQuickLook: (CleanupItem) -> Void
    let onFooterAction: () -> Void

    @Environment(\.controlMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                Divider().opacity(0.5)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(finding.items) { item in
                        FindingItemRow(
                            item: item,
                            isSelected: selection.contains(item.id),
                            isFocused: focusedItemID == item.id,
                            onToggle: { selection.toggle(item) },
                            onFocus: { focusedItemID = item.id },
                            onQuickLook: { onQuickLook(item) }
                        )
                        if item.id != finding.items.last?.id {
                            Divider().opacity(0.3).padding(.leading, 18)
                        }
                    }
                }
                if finding.id.footer != nil || finding.id.footerAction != nil {
                    footer
                }
            }
        }
        .background(Color.opaqueTertiaryFill, in: RoundedRectangle(cornerRadius: CleanupMetrics.findingCardRadius))
        .hairlineRing(cornerRadius: CleanupMetrics.findingCardRadius)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if !finding.actionableItems.isEmpty {
                MixedStateCheckbox(
                    state: selection.selectAllState(for: finding).nsControlState,
                    action: { selection.setAll(in: finding, selected: selection.selectAllState(for: finding) != .all) }
                )
                .frame(width: 18, height: 18)
            } else {
                // Report-only findings (Simulator runtimes) offer no bulk
                // action at all - a lock, not a checkbox, matching every row
                // underneath.
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, height: 18)
            }

            Button {
                withAnimation(.easeInOut(duration: CleanupMetrics.disclosureRotationDuration)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(finding.id.displayName)
                        .font(.system(size: 14, weight: .semibold))
                    SafetyBadge(level: finding.id.safety)
                    let selectedCount = finding.items.filter { selection.contains($0.id) }.count
                    if selectedCount > 0 {
                        Text("\(selectedCount) selected")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(Color.accentColor)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                }
                Text(finding.id.reason)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteFormatter.string(fromBytes: finding.reclaimableBytes))
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                Text("\(finding.items.count) item\(finding.items.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: CleanupMetrics.disclosureRotationDuration)) {
                isExpanded.toggle()
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline) {
            if let footer = finding.id.footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let footerAction = finding.id.footerAction {
                Button(footerAction, action: onFooterAction)
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct FindingItemRow: View {
    let item: CleanupItem
    let isSelected: Bool
    let isFocused: Bool
    let onToggle: () -> Void
    let onFocus: () -> Void
    let onQuickLook: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if item.isReportOnly {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16, height: 16)
                    .help(item.hint ?? "")
            } else {
                Toggle("", isOn: Binding(get: { isSelected }, set: { _ in onToggle() }))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13))
                Text(item.detail)
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let note = item.note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Text(ByteFormatter.string(fromBytes: item.sizeBytes))
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Button(action: onQuickLook) {
                    Image(systemName: "eye")
                }
                .help("Quick Look")

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.revealPath)])
                } label: {
                    Image(systemName: "folder")
                }
                .help("Reveal in Finder")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.12) : (isFocused ? Color.primary.opacity(0.04) : Color.clear))
        .onTapGesture(perform: onFocus)
    }
}
