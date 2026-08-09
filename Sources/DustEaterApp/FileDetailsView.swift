import SwiftUI
import DustEaterCore

struct FileDetailsView: View {
    let node: FileNode
    let root: FileNode

    private var filePath: String {
        node.path
    }

    private var fileTypeIcon: String {
        let pathExt = (node.path as NSString).pathExtension.lowercased()

        if pathExt.isEmpty {
            return "doc.text.fill"
        }

        switch pathExt {
        case "pdf": return "doc.pdf.fill"
        case "doc", "docx": return "doc.word.fill"
        case "xls", "xlsx": return "doc.richtext.fill"
        case "ppt", "pptx": return "doc.presentation.fill"
        case "jpg", "jpeg", "png", "gif", "webp": return "photo.fill"
        case "mp4", "mov", "mkv": return "video.fill"
        case "mp3", "wav", "flac": return "music.note"
        case "zip", "rar", "7z": return "doc.zipper"
        case "app": return "app.fill"
        default: return "doc.fill"
        }
    }

    private var formattedSize: String {
        ByteFormatter.string(fromBytes: node.size)
    }

    private var fileExtension: String {
        let pathExt = (node.path as NSString).pathExtension
        return pathExt.isEmpty ? "No extension" : pathExt.uppercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: DustEaterTheme.Spacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("File Details")
                            .font(DustEaterTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)

                        Text(node.name)
                            .font(DustEaterTheme.Typography.headline)
                            .lineLimit(1)
                    }
                    Spacer()
                }
            }
            .padding(DustEaterTheme.Spacing.md)
            .background(.bar)

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: DustEaterTheme.Spacing.lg) {
                    // File icon and basic info
                    VStack(alignment: .center, spacing: DustEaterTheme.Spacing.md) {
                        Image(systemName: fileTypeIcon)
                            .font(.system(size: 48))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .center, spacing: DustEaterTheme.Spacing.sm) {
                            Text(node.name)
                                .font(DustEaterTheme.Typography.headline)
                                .lineLimit(2)

                            Text(formattedSize)
                                .font(DustEaterTheme.Typography.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(DustEaterTheme.Spacing.lg)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)

                    // Details
                    VStack(alignment: .leading, spacing: DustEaterTheme.Spacing.md) {
                        // File Type
                        DetailRow(label: "Type", value: fileExtension)

                        Divider()

                        // Size
                        DetailRow(label: "Size", value: formattedSize)

                        Divider()

                        // Path
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Path")
                                .font(DustEaterTheme.Typography.caption)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            Text(filePath)
                                .font(.callout.monospaced())
                                .foregroundStyle(.primary)
                                .lineLimit(5)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(DustEaterTheme.Spacing.md)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                }
                .padding(DustEaterTheme.Spacing.md)
            }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(DustEaterTheme.Typography.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(value)
                .font(DustEaterTheme.Typography.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }
}
