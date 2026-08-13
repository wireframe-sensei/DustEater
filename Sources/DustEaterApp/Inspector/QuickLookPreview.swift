import QuickLookUI
import SwiftUI

/// Thin wrapper around `QLPreviewView`, following the same
/// `NSViewRepresentable` shape as `MixedStateCheckbox` (`makeNSView` /
/// `updateNSView` / `makeCoordinator`), plus `dismantleNSView`, since a
/// Quick Look session needs an explicit close rather than just being left
/// to deinit.
struct QuickLookPreview: NSViewRepresentable {
    let path: String

    func makeNSView(context: Context) -> QLPreviewView {
        // QuickLookUI's header predates nullability annotations, so Swift
        // imports `initWithFrame:style:` as returning an Optional even
        // though it doesn't actually fail on a live system - QuickLookUI
        // has shipped as a system framework since macOS 10.6. Force-
        // unwrapping here is the same trade-off any other "unannotated but
        // effectively always non-nil" system API import requires.
        let view = QLPreviewView(frame: .zero, style: .normal)!
        // `shouldCloseWithWindow` defaults to true, which keeps the Quick
        // Look session alive for the whole window's lifetime. Wrong here:
        // this view comes and goes with whichever file is selected, not
        // with the window. Turning it off makes the explicit `close()` in
        // `dismantleNSView` below required, per the QuickLookUI header.
        view.shouldCloseWithWindow = false
        view.autostarts = true
        context.coordinator.lastPath = path
        view.previewItem = URL(fileURLWithPath: path) as NSURL
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        // Reassigning `previewItem` re-runs Quick Look's preview generator,
        // so this only happens on an actual path change - not on every
        // SwiftUI body re-evaluation the surrounding view triggers for
        // unrelated reasons (selection changing elsewhere, the action bar's
        // own animations), which would otherwise reload and flicker the
        // preview on every such update.
        guard context.coordinator.lastPath != path else { return }
        context.coordinator.lastPath = path
        nsView.previewItem = URL(fileURLWithPath: path) as NSURL
    }

    static func dismantleNSView(_ nsView: QLPreviewView, coordinator: Coordinator) {
        nsView.close()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastPath: String?
    }
}

/// Wraps `QuickLookPreview` with the cases a bare `QLPreviewView` doesn't
/// handle on its own: nothing selected, and the selected file no longer
/// existing (the post-deletion / moved-externally case). Quick Look itself
/// silently falls back to a generic icon for a type it has no generator
/// for rather than erroring, so a persistent "Reveal in Finder" button
/// underneath means even a blank or generic preview still leaves the user
/// somewhere to go, rather than a dead end.
struct QuickLookPreviewPane: View {
    let path: String?
    let onRunAgain: () -> Void

    var body: some View {
        VStack(spacing: DustEaterTheme.Spacing.sm) {
            content

            if let path, FileManager.default.fileExists(atPath: path) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .font(.control)
                .buttonStyle(.bordered)
            }
        }
        .padding(DustEaterTheme.Spacing.md)
    }

    @ViewBuilder
    private var content: some View {
        if let path {
            if FileManager.default.fileExists(atPath: path) {
                QuickLookPreview(path: path)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: DustEaterTheme.Radius.md))
            } else {
                emptyState(
                    systemImage: "questionmark.folder",
                    title: "File No Longer Available",
                    message: "This file was deleted or moved since the scan.",
                    actionTitle: "Run Again",
                    action: onRunAgain
                )
            }
        } else {
            emptyState(
                systemImage: "eye",
                title: "Select a File to Preview",
                message: "Choose a file from a duplicate set to see it here.",
                actionTitle: nil,
                action: nil
            )
        }
    }

    private func emptyState(
        systemImage: String,
        title: String,
        message: String,
        actionTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        VStack(spacing: DustEaterTheme.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(DustEaterTheme.Typography.headline)
            Text(message)
                .font(DustEaterTheme.Typography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.control)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    QuickLookPreviewPane(path: nil, onRunAgain: {})
        .frame(width: 400, height: 300)
}
