import SwiftUI
import UserNotifications
import DustEaterCore

/// The Monitoring tab of the `Settings {}` scene - the one place item 8's
/// settings live. Deliberately a tab inside the existing Settings window,
/// not a fourth sidebar item: the main shell's sidebar stays three items
/// (Cleanup / Explore / Apps), per the design handoff.
struct MonitoringSettingsPane: View {
    let settings: MonitoringSettingsStore

    @Environment(\.dismiss) private var dismiss
    @State private var bootVolumeCapacity: Int64 = 0

    private static let lowSpacePresets: [Double] = [5, 10, 15, 20]
    private static let junkGrowthPresets: [Int64] = [1_000_000_000, 5_000_000_000, 10_000_000_000, 20_000_000_000]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                menuBarSection
                Divider()
                tellMeWhenSection
                Text("Both are off until you turn them on, and never fire more than once a day. The defaults are 10% free and 5 GB - change them only if DustEater is too quiet or too noisy.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Divider()
                checkIntervalSection
                Divider()
                footerRow
            }
            .padding(20)
        }
        .task {
            loadBootVolumeCapacity()
        }
        .onChange(of: settings.notifyLowSpace) { _, isOn in
            if isOn { requestNotificationPermissionIfNeeded() }
        }
        .onChange(of: settings.notifyJunkGrowth) { _, isOn in
            if isOn { requestNotificationPermissionIfNeeded() }
        }
    }

    private var menuBarSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show DustEater in the menu bar")
                        .font(.system(size: 13, weight: .medium))
                    Text("A capacity gauge and the free-space figure.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { settings.showInMenuBar }, set: { settings.showInMenuBar = $0 }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            HStack {
                Text("When the bar is crowded")
                    .font(.system(size: 12))
                Spacer()
                Picker("", selection: Binding(get: { settings.glanceMode }, set: { settings.glanceMode = $0 })) {
                    Text("Keep the figure").tag(MonitoringSettingsStore.GlanceMode.figureAndGauge)
                    Text("Gauge only").tag(MonitoringSettingsStore.GlanceMode.gaugeOnly)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .disabled(!settings.showInMenuBar)
            .opacity(settings.showInMenuBar ? 1 : 0.4)
        }
    }

    private var tellMeWhenSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TELL ME WHEN")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(.tertiary)

            thresholdRow(
                title: "Free space drops below a threshold",
                isOn: Binding(get: { settings.notifyLowSpace }, set: { settings.notifyLowSpace = $0 }),
                pillLabel: lowSpacePillLabel
            ) {
                Menu {
                    ForEach(Self.lowSpacePresets, id: \.self) { preset in
                        Button(lowSpaceLabel(for: preset)) { settings.lowSpaceThresholdPercent = preset }
                    }
                } label: {
                    Text(lowSpacePillLabel)
                }
            }

            thresholdRow(
                title: "Reclaimable caches pass a threshold",
                isOn: Binding(get: { settings.notifyJunkGrowth }, set: { settings.notifyJunkGrowth = $0 }),
                pillLabel: ByteFormatter.string(fromBytes: settings.junkGrowthThresholdBytes)
            ) {
                Menu {
                    ForEach(Self.junkGrowthPresets, id: \.self) { preset in
                        Button(ByteFormatter.string(fromBytes: preset)) { settings.junkGrowthThresholdBytes = preset }
                    }
                } label: {
                    Text(ByteFormatter.string(fromBytes: settings.junkGrowthThresholdBytes))
                }
            }
        }
    }

    private func thresholdRow<PillContent: View>(
        title: String,
        isOn: Binding<Bool>,
        pillLabel: String,
        @ViewBuilder pill: () -> PillContent
    ) -> some View {
        HStack {
            Toggle(title, isOn: isOn)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
            Spacer()
            pill()
                .font(.system(size: 11).monospacedDigit())
                .menuStyle(.button)
                .fixedSize()
        }
    }

    private var checkIntervalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Check every")
                    .font(.system(size: 12))
                Spacer()
                Text("6 hours")
                    .font(.system(size: 11).monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.opaqueTertiaryFill, in: Capsule())
            }
            Text("Monitoring re-runs only the fast checks - caches, downloads and unused apps. It never walks your whole disk in the background.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var footerRow: some View {
        HStack {
            Text("Findings shown in the menu bar come from the last check, not live.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Done") { dismiss() }
                .font(.control)
                .buttonStyle(.borderedProminent)
        }
    }

    private var lowSpacePillLabel: String {
        lowSpaceLabel(for: settings.lowSpaceThresholdPercent)
    }

    private func lowSpaceLabel(for percent: Double) -> String {
        guard bootVolumeCapacity > 0 else { return "\(Int(percent))%" }
        let absoluteBytes = Int64(Double(bootVolumeCapacity) * percent / 100)
        return "\(Int(percent))% · \(ByteFormatter.string(fromBytes: absoluteBytes))"
    }

    private func loadBootVolumeCapacity() {
        if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey]),
           let total = values.volumeTotalCapacity {
            bootVolumeCapacity = Int64(total)
        }
    }

    private func requestNotificationPermissionIfNeeded() {
        guard !settings.hasRequestedNotificationPermission else { return }
        settings.hasRequestedNotificationPermission = true
        // See `StatusItemController.isRunningAsPackagedApp` - `UNUserNotificationCenter`
        // crashes outright outside a real `.app` bundle (confirmed live), which
        // `swift run`/local dev and CI both are.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
