import SwiftUI
import DustEaterCore

struct UninstallConfirmationSheet: View {
    let displayName: String
    let selection: AppUninstallSelection
    let appSource: AppRowItem.AppRowItemSource
    let totalBytesToRecover: Int64

    @Binding var isDeleting: Bool
    @Binding var errorMessage: String?
    let onConfirm: () -> Void

    @State private var displayedBytes: Int64 = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.controlMetrics) private var metrics

    var selectedPaths: [String] {
        Array(selection.includedItemPaths).sorted()
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.red.opacity(0.7))

                Text("Confirm Uninstall")
                    .font(.headline)

                Text("Uninstall \(displayName)?")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)

            // Animated byte count
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

            // Developer tools warning
            if case .developerTool = appSource {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Text("Developer Tool Data")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    Text("This looks like data used by a developer tool (package manager, build cache, etc.), not leftover from an uninstalled app. Deleting it may require re-downloading packages or rebuilding caches next time you use it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
                .frame(maxWidth: .infinity)
            }

            // Uncertain orphan warning
            if case .orphaned(let orphan) = appSource, orphan.isVendorSibling {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Text("Shared Infrastructure")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    Text("This item shares a folder with another app that's still installed. It may be active shared infrastructure (an updater, sync service, or shared cache) rather than truly leftover data. We can't confirm it's safe to delete - verify manually if unsure.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
                .frame(maxWidth: .infinity)
            }

            // File list
            VStack(alignment: .leading, spacing: 0) {
                Text("Files to remove:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if case .installed(let entity) = appSource, selection.includeAppBundle {
                            HStack(spacing: 8) {
                                Image(systemName: "app")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)
                                Text(entity.appPath)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(Color(nsColor: .separatorColor).opacity(0.2))
                            .cornerRadius(4)
                        }

                        ForEach(selectedPaths, id: \.self) { path in
                            HStack(spacing: 8) {
                                Image(systemName: "folder")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)
                                Text(path)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(Color(nsColor: .separatorColor).opacity(0.2))
                            .cornerRadius(4)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
            .cornerRadius(8)
            .frame(maxHeight: 200)

            // Error message
            if let errorMessage = errorMessage {
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

            // Buttons
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .font(.control)
                .buttonStyle(.bordered)
                .disabled(isDeleting)

                Spacer()

                Button(action: onConfirm) {
                    if isDeleting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Label("Move to Trash", systemImage: "trash")
                    }
                }
                .font(.control)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isDeleting)
            }
            .padding(20)
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                displayedBytes = totalBytesToRecover
            }
        }
    }
}

#Preview {
    @Previewable @State var isDeleting = false
    @Previewable @State var errorMessage: String?

    return UninstallConfirmationSheet(
        displayName: "Example App",
        selection: AppUninstallSelection(orphan: OrphanedAppData(
            inferredIdentifier: "com.example.app",
            items: [
                RelatedStorageItem(category: .caches, path: "/Library/Caches/com.example.app", size: 1024 * 1024 * 100),
                RelatedStorageItem(category: .applicationSupport, path: "/Library/Application Support/com.example.app", size: 1024 * 1024 * 50),
            ]
        )),
        appSource: .orphaned(OrphanedAppData(
            inferredIdentifier: "com.example.app",
            items: [
                RelatedStorageItem(category: .caches, path: "/Library/Caches/com.example.app", size: 1024 * 1024 * 100),
                RelatedStorageItem(category: .applicationSupport, path: "/Library/Application Support/com.example.app", size: 1024 * 1024 * 50),
            ]
        )),
        totalBytesToRecover: 1024 * 1024 * 150,
        isDeleting: $isDeleting,
        errorMessage: $errorMessage,
        onConfirm: {}
    )
}
