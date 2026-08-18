import Foundation

/// The eight browse-by-type buckets Explore's Type board shows, per the
/// design handoff. Order here has no meaning - the Type board ranks by
/// total size, not this declaration order.
public enum FileTypeCategory: String, Sendable, CaseIterable, Identifiable, Equatable {
    case applications, codeAndProjects, videos, photos, audio, documents, archivesAndInstallers, other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .applications: return "Applications"
        case .codeAndProjects: return "Code & Projects"
        case .videos: return "Videos"
        case .photos: return "Photos"
        case .audio: return "Audio"
        case .documents: return "Documents"
        case .archivesAndInstallers: return "Archives & Installers"
        case .other: return "Other"
        }
    }

    /// SF Symbol name for the type tile's icon square. Accent color is a
    /// display concern with no `DustEaterCore` equivalent - see
    /// `Sources/DustEaterApp/Explore` for the color mapping.
    public var systemImage: String {
        switch self {
        case .applications: return "app.badge"
        case .codeAndProjects: return "chevron.left.forwardslash.chevron.right"
        case .videos: return "video"
        case .photos: return "photo"
        case .audio: return "waveform"
        case .documents: return "doc.text"
        case .archivesAndInstallers: return "archivebox"
        case .other: return "questionmark.folder"
        }
    }
}
