import SwiftUI
import AppKit
import DustEaterCore

struct TargetCardView: View {
    let target: PurgeTarget
    let onDelete: () -> Void

    @Environment(\.controlMetrics) private var metrics
    @State private var showDetails = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(target.definition.title)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                SafetyBadge(level: target.safety)
            }

            Text(ByteFormatter.string(fromBytes: target.sizeBytes))
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())

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
        .sheet(isPresented: $showDetails) {
            TargetDetailsSheet(target: target)
        }
        .alert("Delete \(target.definition.title)?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    @ViewBuilder
    private var footer: some View {
        if target.safety == .reportOnly {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: target.path)])
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
            .font(.system(size: 13, weight: .medium))
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else {
            HStack(spacing: 8) {
                Spacer()
                Button {
                    showDetails = true
                } label: {
                    Label("View Details", systemImage: "info.circle")
                }
                .font(.system(size: 13, weight: .medium))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .font(.system(size: 13, weight: .medium))
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
        }
    }
}

struct TargetDetailsSheet: View {
    let target: PurgeTarget
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(target.definition.title)
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(target.definition.detail)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.primary)

                    if let rebuildCommand = target.definition.rebuildCommand {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Rebuild with:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(rebuildCommand)
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .foregroundStyle(.primary)
                                .padding(8)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(4)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 400, minHeight: 300)
    }
}
