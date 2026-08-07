import SwiftUI
import DustEaterCore

struct ScanProgressView: View {
    let progress: ScanProgressSnapshot
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)

            Text("\(progress.itemsScanned) items scanned")
                .font(.headline)

            Text(ByteFormatter.string(fromBytes: progress.bytesScanned))
                .foregroundStyle(.secondary)

            Text(progress.currentPath)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 320)

            Button("Cancel", action: onCancel)
                .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
