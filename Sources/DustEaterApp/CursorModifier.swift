import SwiftUI
import AppKit

struct PointingHandCursorModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    NSCursor.pointingHand.set()
                case .ended:
                    NSCursor.arrow.set()
                }
            }
    }
}

extension View {
    func pointingHandCursor() -> some View {
        self.modifier(PointingHandCursorModifier())
    }
}
