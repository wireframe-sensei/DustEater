import SwiftUI
import DustEaterCore

/// Pull-down menu of `SmartSelectionRule`s, plus "Clear Selection" -
/// grouped options belong in a `Menu`, not a per-row control, matching the
/// convention `FileTreeListView`'s file already documents (a per-row `Menu`
/// crushes names down at sidebar width; grouped actions belong in one
/// toolbar-level control).
struct SmartSelectMenu: View {
    let isEnabled: Bool
    let onApply: (SmartSelectionRule) -> Void
    let onClear: () -> Void

    var body: some View {
        Menu {
            ForEach(SmartSelectionRule.allCases) { rule in
                Button(rule.displayName) {
                    onApply(rule)
                }
                .font(.control)
            }

            Divider()

            Button("Clear Selection", action: onClear)
                .font(.control)
        } label: {
            Label("Smart Select", systemImage: "wand.and.stars")
        }
        .disabled(!isEnabled)
        .help("Select duplicates in bulk - always keeps at least one copy of every file")
    }
}

#Preview {
    SmartSelectMenu(isEnabled: true, onApply: { _ in }, onClear: {})
        .padding()
}
