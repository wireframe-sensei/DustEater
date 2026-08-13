import Foundation

/// A single file surfaced by `LargeFileFinder`, pairing its stat facts with
/// the best-available "last actually used" date.
public struct LargeFileEntry: Sendable, Identifiable {
    public var id: String { file.path }

    public let file: InspectedFile
    /// Best-available last-used date - Spotlight's `kMDItemLastUsedDate`
    /// when available, falling back to filesystem modification date (see
    /// `AppLastUsedDateProvider`, reused here). Deliberately not raw
    /// `st_atime`: on macOS, access time is routinely bumped by Spotlight
    /// indexing, Time Machine, and antivirus scanners, so it reads as
    /// "recently used" for files nobody has actually opened.
    ///
    /// `nil` means genuinely unknown, not "never used" - callers must never
    /// treat an unknown date as evidence of staleness. See
    /// `LargeFileFinder.matches`.
    public let lastUsedDate: Date?

    public init(file: InspectedFile, lastUsedDate: Date?) {
        self.file = file
        self.lastUsedDate = lastUsedDate
    }
}
