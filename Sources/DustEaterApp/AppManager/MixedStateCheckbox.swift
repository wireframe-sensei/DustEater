import SwiftUI

/// Tri-state checkbox for "select all" controls, backed by a plain
/// `NSControl.StateValue` rather than any one feature's selection type -
/// both App Manager's `AppUninstallSelection.SelectAllState` and the
/// duplicate inspector's own selection state map onto it via the
/// `nsControlState` extensions below, so this stays a shared, feature-
/// agnostic component.
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

extension AppUninstallSelection.SelectAllState {
    var nsControlState: NSControl.StateValue {
        switch self {
        case .all: .on
        case .none: .off
        case .mixed: .mixed
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
