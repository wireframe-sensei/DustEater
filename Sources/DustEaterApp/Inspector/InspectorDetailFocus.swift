import Foundation

/// What the inspector's detail pane is currently showing - a single file's
/// Quick Look preview, a duplicate set's side-by-side comparison, or
/// nothing selected yet.
///
/// One enum rather than two independent optionals (a previewed path plus a
/// separately-tracked selected set) so the two states can't both be "set"
/// at once and leave it ambiguous which one the detail pane should render.
enum InspectorDetailFocus: Equatable {
    case none
    case file(String)
    case set(String)
}
