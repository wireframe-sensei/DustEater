import AppKit
import SwiftUI
import UserNotifications
import DustEaterCore

/// Owns the menu bar item, its dropdown, the 6-hour check timer, and the
/// two monitoring notifications. Created once at the `DustEaterApp` level
/// (a plain reference type held via `@State` purely for identity stability,
/// same pattern as `TreemapCache`/`ContentView.coordinator`) so it survives
/// the main window closing - the whole point of a menu bar presence is that
/// it doesn't depend on a window being open.
///
/// An `NSObject` subclass (needed for `#selector` target-action on the
/// status item button and for `UNUserNotificationCenterDelegate`
/// conformance), not `@Observable` itself - nothing in SwiftUI reads this
/// controller's own state directly; it reacts *to* `MonitoringSettingsStore`
/// via `withObservationTracking`, the non-View way to observe an
/// `@Observable` object, re-registering itself after each firing since
/// `withObservationTracking`'s `onChange` only fires once per registration.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate, UNUserNotificationCenterDelegate {
    private enum NotificationCategoryID: String {
        case lowSpace = "DustEater.LowSpace"
        case junkGrowth = "DustEater.JunkGrowth"
    }

    private enum NotificationActionID: String {
        case review = "DustEater.Review"
        case notifyLess = "DustEater.NotifyLess"
    }

    private var settings: MonitoringSettingsStore?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var checkTimer: Timer?

    private var onReview: (() -> Void)?
    private var onRescan: (() -> Void)?
    private var onOpenSettings: (() -> Void)?

    /// `UNUserNotificationCenter.current()` throws an uncaught
    /// `NSInternalInconsistencyException` ("bundleProxyForCurrentProcess is
    /// nil") and crashes outright when the running process isn't inside a
    /// real `.app` bundle - confirmed live, not assumed, the same way
    /// `DustEaterApp.setDockIcon`'s `Bundle.module` guard was. `swift run`/
    /// the raw `.build/debug/DustEaterApp` executable used for local dev
    /// and CI hits this every time; only a packaged release `.app` has a
    /// real bundle proxy. Everything that touches
    /// `UNUserNotificationCenter` - the delegate, category registration,
    /// and actually sending a notification - must stay behind this guard.
    private static var isRunningAsPackagedApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private(set) var lastResult: MonitoringCheckResult?
    private var lastCapacity: (total: Int64, free: Int64) = (0, 0)
    /// The volume the dropdown's capacity line and the low-space
    /// notification check against - kept as whatever was last scanned
    /// (`updateVolumePath`), defaulting to the boot volume before any scan
    /// has happened this session, same fallback Welcome step 3 uses.
    private var volumePath = "/"

    func attach(
        settings: MonitoringSettingsStore,
        onReview: @escaping () -> Void,
        onRescan: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        guard self.settings == nil else { return }
        self.settings = settings
        self.onReview = onReview
        self.onRescan = onRescan
        self.onOpenSettings = onOpenSettings

        if Self.isRunningAsPackagedApp {
            UNUserNotificationCenter.current().delegate = self
            registerNotificationCategories()
        }
        observeSettings()
        applyVisibility()
    }

    func updateVolumePath(_ path: String) {
        volumePath = path
        updateCapacitySnapshot()
        updateButtonImage()
    }

    // MARK: - Reacting to settings changes

    private func observeSettings() {
        guard let settings else { return }
        withObservationTracking {
            _ = settings.showInMenuBar
            _ = settings.glanceMode
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.applyVisibility()
                self?.observeSettings()
            }
        }
    }

    private func applyVisibility() {
        guard let settings else { return }
        if settings.showInMenuBar {
            showStatusItemIfNeeded()
            startTimerIfNeeded()
            Task { await runCheckAndRefresh() }
        } else {
            hideStatusItem()
            checkTimer?.invalidate()
            checkTimer = nil
        }
    }

    // MARK: - Status item + button image

    private func showStatusItemIfNeeded() {
        guard statusItem == nil else {
            updateButtonImage()
            return
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.imagePosition = .imageOnly
        statusItem = item
        updateCapacitySnapshot()
        updateButtonImage()
    }

    private func hideStatusItem() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
        popover = nil
    }

    private func updateCapacitySnapshot() {
        guard let values = try? URL(fileURLWithPath: volumePath).resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
              let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacity else { return }
        lastCapacity = (Int64(total), Int64(available))
    }

    private func volumeDisplayName() -> String {
        (try? URL(fileURLWithPath: volumePath).resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? "This Mac"
    }

    private func updateButtonImage() {
        guard let button = statusItem?.button, let settings else { return }
        let usageFraction = lastCapacity.total > 0
            ? Double(lastCapacity.total - lastCapacity.free) / Double(lastCapacity.total)
            : 0
        let view = MenuBarGlanceView(
            usageFraction: usageFraction,
            freeText: ByteFormatter.string(fromBytes: lastCapacity.free),
            showsFigure: settings.glanceMode == .figureAndGauge
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        button.image = renderer.nsImage
    }

    // MARK: - Dropdown

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }

        let content = MenuBarDropdownView(
            volumeName: volumeDisplayName(),
            freeBytes: lastCapacity.free,
            purgeableBytes: DiskTelemetryService.purgeableBytes(atPath: volumePath),
            result: lastResult,
            isPaused: settings?.isPaused ?? false,
            onReview: { [weak self] in self?.closePopover(then: self?.onReview) },
            onRescan: { [weak self] in self?.closePopover(then: self?.onRescan) },
            onTogglePause: { [weak self] in self?.settings?.isPaused.toggle() },
            onOpenSettings: { [weak self] in self?.closePopover(then: self?.onOpenSettings) },
            onQuit: { NSApp.terminate(nil) }
        )

        let hostingController = NSHostingController(rootView: content)
        hostingController.sizingOptions = [.preferredContentSize]

        let newPopover = NSPopover()
        newPopover.behavior = .transient
        newPopover.contentViewController = hostingController
        newPopover.delegate = self
        // Belt-and-suspenders on top of `sizingOptions`: confirmed live that
        // relying on `preferredContentSize` alone can still show the
        // popover at effectively zero height (a highlighted status item
        // button with no visible panel below it) depending on exactly when
        // AppKit asks for it relative to SwiftUI's first layout pass. An
        // explicit `contentSize` here is authoritative regardless of that
        // timing - `MenuBarDropdownView` is a fixed 268pt wide and its
        // content (header, up to three finding rows, four menu rows,
        // footer) tops out well under 480pt tall.
        newPopover.contentSize = NSSize(width: 268, height: 480)
        popover = newPopover
        newPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.highlight(true)
    }

    private func closePopover(then action: (() -> Void)?) {
        popover?.performClose(nil)
        action?()
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem?.button?.highlight(false)
    }

    // MARK: - The 6-hour check

    private func startTimerIfNeeded() {
        guard checkTimer == nil else { return }
        checkTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.runCheckAndRefresh()
            }
        }
    }

    private func runCheckAndRefresh() async {
        guard let settings, settings.showInMenuBar else { return }
        let result = await MonitoringChecker.run()
        lastResult = result
        updateCapacitySnapshot()
        updateButtonImage()

        guard !settings.isPaused else { return }
        evaluateNotifications(result: result, settings: settings)
    }

    // MARK: - Notifications

    private func registerNotificationCategories() {
        let review = UNNotificationAction(identifier: NotificationActionID.review.rawValue, title: "Review", options: [.foreground])
        let notifyLess = UNNotificationAction(identifier: NotificationActionID.notifyLess.rawValue, title: "Notify Less", options: [.foreground])
        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(identifier: NotificationCategoryID.lowSpace.rawValue, actions: [review, notifyLess], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: NotificationCategoryID.junkGrowth.rawValue, actions: [review, notifyLess], intentIdentifiers: [], options: [])
        ]
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    /// Both triggers are threshold checks against the current 6-hour
    /// snapshot, capped at once per day each (`firedWithinLastDay`) - not a
    /// true delta-since-last-cleanup computation, which would need its own
    /// persisted baseline. Simpler and still matches the rule as stated:
    /// "reclaimable caches pass a threshold."
    private func evaluateNotifications(result: MonitoringCheckResult, settings: MonitoringSettingsStore) {
        let now = Date()

        if settings.notifyLowSpace, lastCapacity.total > 0 {
            let freePercent = Double(lastCapacity.free) / Double(lastCapacity.total) * 100
            if freePercent < settings.lowSpaceThresholdPercent, !firedWithinLastDay(settings.lastLowSpaceNotifiedAt, now: now) {
                sendNotification(
                    category: .lowSpace,
                    title: "\(volumeDisplayName()) is running low",
                    body: "\(ByteFormatter.string(fromBytes: lastCapacity.free)) free, under your \(Int(settings.lowSpaceThresholdPercent))% threshold. DustEater found \(ByteFormatter.string(fromBytes: result.reclaimableBytes)) it can reclaim."
                )
                settings.lastLowSpaceNotifiedAt = now
            }
        }

        if settings.notifyJunkGrowth, result.rebuildableBytes >= settings.junkGrowthThresholdBytes,
           !firedWithinLastDay(settings.lastJunkGrowthNotifiedAt, now: now) {
            sendNotification(
                category: .junkGrowth,
                title: "Caches have built up again",
                body: "\(ByteFormatter.string(fromBytes: result.rebuildableBytes)) of rebuildable caches since you last cleaned up. Nothing of yours is included."
            )
            settings.lastJunkGrowthNotifiedAt = now
        }
    }

    private func firedWithinLastDay(_ date: Date?, now: Date) -> Bool {
        guard let date else { return false }
        return now.timeIntervalSince(date) < 24 * 3600
    }

    private func sendNotification(category: NotificationCategoryID, title: String, body: String) {
        guard Self.isRunningAsPackagedApp else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category.rawValue
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Shown even while DustEater is frontmost - without this, foreground
    /// notifications are suppressed by default, and a low-space warning is
    /// exactly as relevant whether or not the app happens to be in front.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Extracted before hopping to the main actor: `UNNotificationResponse`
        // itself isn't `Sendable`, but the one `String` this needs out of it is.
        let actionIdentifier = response.actionIdentifier
        await MainActor.run {
            switch actionIdentifier {
            case NotificationActionID.review.rawValue, UNNotificationDefaultActionIdentifier:
                onReview?()
            case NotificationActionID.notifyLess.rawValue:
                onOpenSettings?()
            default:
                break
            }
        }
    }
}
