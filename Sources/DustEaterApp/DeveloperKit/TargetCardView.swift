import SwiftUI
import AppKit
import DustEaterCore

struct TargetCardView: View {
    let target: PurgeTarget
    let isSelected: Bool
    let onToggle: () -> Void
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
        .glassBackground(.ultraThinMaterial, cornerRadius: 12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
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
            HStack {
                Spacer()
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: target.path)])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .font(.system(size: 13, weight: .medium))
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        } else {
            HStack(spacing: 12) {
                Toggle(
                    "Include in purge",
                    isOn: Binding(get: { isSelected }, set: { _ in onToggle() })
                )
                .toggleStyle(.checkbox)
                .labelsHidden()

                Spacer()

                Button {
                    showDetails = true
                } label: {
                    Label("View Details", systemImage: "info.circle")
                }
                .font(.system(size: 13, weight: .medium))
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .font(.system(size: 13, weight: .medium))
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            }
        }
    }
}

struct TargetDetailsSheet: View {
    let target: PurgeTarget
    @Environment(\.dismiss) private var dismiss

    private var isAppRunning: Bool {
        guard let bundleID = target.definition.blockingAppBundleID else { return false }
        return FileOperations.isAppRunning(bundleIdentifier: bundleID)
    }

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
                VStack(alignment: .leading, spacing: 14) {
                    // Description
                    Text(target.definition.detail)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.primary)

                    Divider()

                    // Size
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Size")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(ByteFormatter.string(fromBytes: target.sizeBytes))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                    }

                    Divider()

                    // Safety Level
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Safety Level")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        SafetyBadge(level: target.safety)
                    }

                    Divider()

                    // Path
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Location")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(target.path)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .truncationMode(.middle)
                    }

                    Divider()

                    // App Status
                    if target.definition.blockingAppBundleID != nil {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("App Status")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Image(systemName: isAppRunning ? "circle.fill" : "circle")
                                    .font(.system(size: 8))
                                    .foregroundStyle(isAppRunning ? .orange : .secondary)
                                Text(isAppRunning ? "Running (delete will be skipped)" : "Not running")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(isAppRunning ? .orange : .secondary)
                            }
                        }

                        Divider()
                    }

                    // Hint
                    if let hint = target.definition.hint {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Note")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(hint)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(.primary)
                        }

                        Divider()
                    }

                    // Rebuild Command
                    if let rebuildCommand = target.definition.rebuildCommand {
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
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 500, minHeight: 400)
    }
}
