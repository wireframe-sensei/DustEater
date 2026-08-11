import SwiftUI

struct MixedStateCheckbox: NSViewRepresentable {
    let state: AppUninstallSelection.SelectAllState
    let action: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: "", target: context.coordinator, action: #selector(Coordinator.clicked))
        button.allowsMixedState = true
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.action = action

        switch state {
        case .all:
            nsView.state = .on
        case .none:
            nsView.state = .off
        case .mixed:
            nsView.state = .mixed
        }
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
            MixedStateCheckbox(state: .all, action: {})
            Text("All selected")
        }

        HStack {
            MixedStateCheckbox(state: .mixed, action: {})
            Text("Partially selected")
        }

        HStack {
            MixedStateCheckbox(state: .none, action: {})
            Text("None selected")
        }
    }
    .padding()
}
