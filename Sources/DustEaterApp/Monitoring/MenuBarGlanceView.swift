import SwiftUI

/// The menu bar item's own content - a 13pt capacity ring, always drawn,
/// plus the free-space figure in mono tabular, which drops when the bar is
/// crowded (`showsFigure`, driven by `MonitoringSettingsStore.glanceMode`).
/// Rendered off-screen via `ImageRenderer` and assigned to the status
/// item's button image, rather than hosted live in the status bar - an
/// `NSStatusBarButton` doesn't reliably host an `NSHostingView` subview the
/// way a normal window content view does.
struct MenuBarGlanceView: View {
    let usageFraction: Double
    let freeText: String
    let showsFigure: Bool

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color(nsColor: .labelColor).opacity(0.3), lineWidth: 2)
                Circle()
                    // A small floor so the ring always shows *something*
                    // even at 0% used, rather than looking like a blank
                    // circle that could be mistaken for "no data yet".
                    .trim(from: 0, to: max(0.03, min(1, usageFraction)))
                    .stroke(Color(nsColor: .labelColor), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 13, height: 13)

            if showsFigure {
                Text(freeText)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Color(nsColor: .labelColor))
            }
        }
        .padding(.horizontal, 2)
        .fixedSize()
    }
}
