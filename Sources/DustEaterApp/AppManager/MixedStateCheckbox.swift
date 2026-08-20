import SwiftUI

/// Tri-state checkbox for "select all" controls, backed by a plain
/// `NSControl.StateValue` rather than any one feature's selection type -
/// `FindingGroupView` maps `SelectionStore.SelectAllState` onto it via the
/// `nsControlState` computed property already defined on that type, so
/// this stays a shared, feature-agnostic component rather than knowing
/// about any one selection type itself.
struct MixedStateCheckbox: NSViewRepresentable {
    let state: NSControl.StateValue
    let action: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: "", target: context.coordinator, action: #selector(Coordinator.clicked))
        button.allowsMixedState = true
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.action = action
        nsView.state = state
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func clicked() {
            action()
        }
    }
}

#Preview {
    VStack {
        HStack {
            MixedStateCheckbox(state: .on, action: {})
            Text("All selected")
        }

        HStack {
            MixedStateCheckbox(state: .mixed, action: {})
            Text("Partially selected")
        }

        HStack {
            MixedStateCheckbox(state: .off, action: {})
            Text("None selected")
        }
    }
    .padding()
}
