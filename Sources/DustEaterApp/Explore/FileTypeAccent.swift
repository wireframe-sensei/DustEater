import SwiftUI
import DustEaterCore

/// `FileTypeCategory`'s accent color - a display concern with no
/// `DustEaterCore` equivalent, so it lives here rather than on the Core
/// enum itself (the same split `CleanupFindingID`'s dot colors already use
/// in `FindingGroupView`/`ScanningCardView`). Mapped to real system accent
/// colors, never a literal RGB value, per the design system conventions.
extension FileTypeCategory {
    var accentColor: Color {
        switch self {
        case .applications: return Color(nsColor: .systemBlue)
        case .codeAndProjects: return Color(nsColor: .systemTeal)
        case .videos: return Color(nsColor: .systemPurple)
        case .photos: return Color(nsColor: .systemPink)
        case .audio: return Color(nsColor: .systemOrange)
        case .documents: return Color(nsColor: .systemGreen)
        case .archivesAndInstallers: return Color(nsColor: .systemYellow)
        case .other: return Color(nsColor: .systemGray)
        }
    }
}
