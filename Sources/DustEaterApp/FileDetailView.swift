import SwiftUI
import DustEaterCore

struct FileDetailView: View {
    let node: FileNode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: node.isDirectory ? "folder.fill" : "doc")
                    .font(.largeTitle)
                    .foregroundStyle(node.isDirectory ? .blue : .secondary)
                VStack(alignment: .leading) {
                    Text(node.name)
                        .font(.title2.bold())
                    Text(node.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Divider()

            LabeledContent("Size", value: ByteFormatter.string(fromBytes: node.size))
            LabeledContent("Items", value: "\(node.itemCount)")
            LabeledContent("Type", value: node.isDirectory ? "Folder" : "File")

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
