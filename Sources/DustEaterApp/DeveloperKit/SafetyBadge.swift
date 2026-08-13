import SwiftUI
import DustEaterCore

/// A small pill showing a target's `PurgeSafetyLevel`. The HIG kit has no
/// badge component (see `macos-hig-design-system/references/components.md`),
/// so this is built from primitives rather than a system control.
struct SafetyBadge: View {
    let level: PurgeSafetyLevel

    private var label: String {
        switch level {
        case .safe: "Safe"
        case .rebuildable: "Rebuildable"
        case .caution: "Caution"
        case .reportOnly: "Report Only"
        }
    }

    private var tint: Color {
        switch level {
        case .safe: Color(nsColor: .systemGreen)
        case .rebuildable: Color(nsColor: .systemTeal)
        case .caution: Color(nsColor: .systemOrange)
        case .reportOnly: Color(nsColor: .systemGray)
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            if level == .reportOnly {
                Image(systemName: "info.circle")
                    .font(.system(size: 9, weight: .medium))
            }
            Text(label)
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(tint)
        // A literal `Capsule()`, not `metrics.buttonShape`:
        // `ControlMetrics.isCapsule` governs controls that draw themselves
        // as compact buttons, and a static badge like this one is not a
        // control - the same distinction `DiskCardView` already documents
        // for its own corner-radius choice in `DiskHomeView.swift`.
        .background(tint.opacity(0.15), in: Capsule())
    }
}
