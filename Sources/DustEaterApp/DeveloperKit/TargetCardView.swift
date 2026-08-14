import SwiftUI
import AppKit
import DustEaterCore

/// One purge target's card: title, measured size, safety badge, a one-line
/// explanation, a rebuild footnote when relevant, and either a toggle or a
/// Reveal-in-Finder action - never both. `.reportOnly` targets never get a
/// toggle at all; see `PurgeSelection.toggle` for the matching hard refusal
/// at the data layer.
struct TargetCardView: View {
    let target: PurgeTarget
    let isSelected: Bool
    let onToggle: () -> Void

    @Environment(\.controlMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(target.definition.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                SafetyBadge(level: target.safety)
            }

            Text(ByteFormatter.string(fromBytes: target.sizeBytes))
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())

            Text(target.definition.detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let rebuildCommand = target.definition.rebuildCommand {
                Text("Rebuilt by: \(rebuildCommand)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 150)
        .padding(16)
        .glassBackground(.ultraThinMaterial, cornerRadius: metrics.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: metrics.cornerRadius)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var footer: some View {
        if target.safety == .reportOnly {
            VStack(alignment: .leading, spacing: 4) {
                if let hint = target.definition.hint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: target.path)])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .font(.control)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else {
            HStack {
                Spacer()
                Toggle(
                    "Include in purge",
                    isOn: Binding(get: { isSelected }, set: { _ in onToggle() })
                )
                .toggleStyle(.checkbox)
                .labelsHidden()
            }
        }
    }
}
