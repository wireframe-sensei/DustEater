import Testing
import SwiftUI
@testable import DustEaterCore

/// Regression coverage for a real bug: `colorForNode` used to call
/// `colorForDirectory(depth:theme:)` without passing `name:`, so every
/// directory silently fell back to the same `name: ""` default. Combined
/// with `depth` being constant across any one treemap render (a render only
/// ever shows one flat level of siblings), every folder in the app rendered
/// as the exact same solid color, in every non-weighted theme.
struct TreemapColorsTests {
    private func directory(named name: String) -> FileNode {
        FileNode(name: name, path: "/root/\(name)", size: 100, isDirectory: true)
    }

    private struct RGB: Hashable {
        let r: Float
        let g: Float
        let b: Float
    }

    /// Compares only hue-bearing RGB components, deliberately ignoring
    /// opacity. `colorForNode` layers a per-sibling opacity nudge on top of
    /// its base color, which on its own is enough to make every resulting
    /// `Color` distinct - including in exactly the broken state this test
    /// guards against, where the *hue* never varied at all because `name:`
    /// wasn't reaching `colorForDirectory`. Comparing full `Color` values
    /// (opacity included) would pass either way and catch nothing.
    private func hueRGB(_ color: Color) -> RGB {
        let resolved = color.resolve(in: EnvironmentValues())
        return RGB(r: resolved.red, g: resolved.green, b: resolved.blue)
    }

    @Test func siblingDirectoriesAtSameDepthGetVariedHues() {
        let names = ["Applications", "Library", "Documents", "Downloads", "Pictures", "Movies", "Music", "Desktop"]
        let hues = Set(
            names.map { hueRGB(TreemapColors.colorForNode(directory(named: $0), depth: 1, theme: .vibrant)) }
        )
        #expect(hues.count > 1)
    }

    @Test func colorForDirectoryVariesByNameAtFixedDepth() {
        let a = TreemapColors.colorForDirectory(depth: 1, name: "Applications", theme: .vibrant)
        let b = TreemapColors.colorForDirectory(depth: 1, name: "Library", theme: .vibrant)
        let c = TreemapColors.colorForDirectory(depth: 1, name: "Downloads", theme: .vibrant)
        #expect(Set([a, b, c]).count > 1)
    }
}
