import SwiftUI
import DustEaterCore

/// The pre-scan welcome flow - three steps, replacing the whole window (no
/// sidebar, no toolbar: there is no disk data yet, so there is nothing for
/// a sidebar to hold). `ContentView` shows this once, gated by
/// `OnboardingStore.hasCompletedOnboarding`; it never reappears just because
/// Full Disk Access is still missing on a later launch - that's what
/// Cleanup's limited-access card (item 9) is for.
struct WelcomeView: View {
    /// Called from step 3's "Start Scan" - hands off to whatever
    /// `ContentView` already does to pick a volume and start scanning
    /// (auto-skip if there's exactly one, otherwise `DiskHomeView`). This
    /// view has no opinion on which path or volume gets scanned.
    let onComplete: () -> Void

    @State private var step = 0

    var body: some View {
        // `GeometryReader` + `minWidth`/`minHeight` (not just `maxWidth:
        // .infinity`) is load-bearing, not decoration: a `ScrollView` sizes
        // its content to the content's own ideal size, so a bare `Spacer`
        // inside it has no extra room to expand into and collapses to its
        // `minLength` - the column ends up pinned to the top-left instead
        // of centred. Telling the content it must be at least the
        // viewport's size gives the Spacers something real to center
        // within, while still letting the column grow taller than the
        // window and scroll if it ever needs to.
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 32)
                    VStack(alignment: .leading, spacing: 26) {
                        StepIndicator(currentStep: step)

                        Group {
                            switch step {
                            case 0: WhatItDoesStepView()
                            case 1: FullDiskAccessStepView(onSkip: { step = 2 })
                            default: PurgeableSpaceStepView()
                            }
                        }

                        footer
                    }
                    .frame(width: 580)
                    Spacer(minLength: 32)
                }
                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
                    .font(.control)
                    .buttonStyle(.bordered)
            }
            Spacer()
            Button(step == 2 ? "Start Scan" : "Continue") {
                if step == 2 {
                    onComplete()
                } else {
                    step += 1
                }
            }
            .font(.control)
            .buttonStyle(.borderedProminent)
        }
    }
}

/// Three equal columns, each a 3pt bar over an uppercase label. Completed
/// and current steps read as done/active (accent bar, primary label);
/// upcoming steps are visibly fainter (quaternary fill, tertiary label).
private struct StepIndicator: View {
    let currentStep: Int
    private let labels = ["What it does", "Full Disk Access", "Purgeable space"]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { index in
                VStack(alignment: .leading, spacing: 6) {
                    Capsule()
                        .fill(index <= currentStep ? Color.accentColor : Color.opaqueQuaternaryFill)
                        .frame(height: 3)
                    Text(labels[index].uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(index <= currentStep ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                }
            }
        }
    }
}

/// Step 1 - the three safety rules stated as promises up front, so the
/// Cleanup screen doesn't have to re-argue them later.
private struct WhatItDoesStepView: View {
    private let promises: [(title: String, body: String)] = [
        ("Nothing is selected for you", "Every checkbox starts empty. DustEater ranks and explains; you decide what goes."),
        ("The Trash is the default destination", "Deletions are recoverable until you empty it, and undo puts them back."),
        ("Your own files are never recommended", "Documents, your Photos library, iCloud Drive files and Time Machine backups are excluded from every scan.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("DustEater finds space you can safely reclaim")
                    .font(.system(size: 26, weight: .bold))
                Text("It reads your disk, ranks what is taking up room, and explains what each item is before you decide. Three things hold for every scan.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(promises.enumerated()), id: \.offset) { index, promise in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(nsColor: .systemGreen))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(promise.title).font(.system(size: 13, weight: .semibold))
                            Text(promise.body).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    if index != promises.count - 1 {
                        Divider().opacity(0.3)
                    }
                }
            }
            .background(Color.opaqueTertiaryFill, in: RoundedRectangle(cornerRadius: 12))
            .hairlineRing(cornerRadius: 12)
        }
    }
}

/// Step 3 - the purgeable-space explanation, illustrated against the boot
/// volume (there's no scan target chosen yet at this point in the flow).
/// The sidebar's own purgeable line (shipped in the Cleanup restructure)
/// repeats this for whichever volume actually gets scanned.
private struct PurgeableSpaceStepView: View {
    @State private var total: Int64 = 0
    @State private var free: Int64 = 0
    @State private var purgeable: Int64 = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Why DustEater and Finder disagree")
                    .font(.system(size: 26, weight: .bold))
                Text("Part of your used space is purgeable: files macOS keeps only while there is room, and releases the moment something needs it. Finder counts it as free. DustEater counts it as used, and names it.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            PurgeableCapacityCard(total: total, free: free, purgeable: purgeable)
        }
        .task {
            loadCapacity()
        }
    }

    private func loadCapacity() {
        if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
           let totalCapacity = values.volumeTotalCapacity, let availableCapacity = values.volumeAvailableCapacity {
            total = Int64(totalCapacity)
            free = Int64(availableCapacity)
        }
        purgeable = DiskTelemetryService.purgeableBytes(atPath: "/")
    }
}

/// A capacity bar (used, then a hatched purgeable segment, then track for
/// free) over three tabular figures. `used` is derived so the three figures
/// always sum to `total` exactly: `available` (from
/// `volumeAvailableCapacityKey`) already excludes purgeable space, so
/// `used = total - free - purgeable`, not `total - free`.
private struct PurgeableCapacityCard: View {
    let total: Int64
    let free: Int64
    let purgeable: Int64

    private var used: Int64 { max(0, total - free - purgeable) }

    private func fraction(_ bytes: Int64) -> CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(bytes) / CGFloat(total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.progressTrack)
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(LinearGradient(colors: [Color(nsColor: .systemOrange), Color(nsColor: .systemRed)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geometry.size.width * fraction(used))
                        ZStack {
                            Rectangle().fill(Color(nsColor: .systemYellow))
                            DiagonalHatch()
                        }
                        .frame(width: geometry.size.width * fraction(purgeable))
                        Spacer(minLength: 0)
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: 10)

            HStack(spacing: 28) {
                capacityFigure(label: "Used", value: used, tint: nil)
                capacityFigure(label: "Purgeable", value: purgeable, tint: Color(nsColor: .systemYellow))
                capacityFigure(label: "Free", value: free, tint: nil)
            }

            Text("You never need to reclaim purgeable space yourself. It is here so the numbers on the next screen make sense - the sidebar repeats this line for the volume you are scanning.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.opaqueTertiaryFill, in: RoundedRectangle(cornerRadius: 14))
        .hairlineRing(cornerRadius: 14)
    }

    private func capacityFigure(label: String, value: Int64, tint: Color?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
            Text(ByteFormatter.string(fromBytes: value))
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
        }
    }
}

/// Decorative diagonal-line fill for the purgeable segment of the capacity
/// bar - there's no system pattern fill for this, so it's drawn directly
/// with `Canvas` rather than an image asset.
private struct DiagonalHatch: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 4
            var x: CGFloat = -size.height
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(path, with: .color(.black.opacity(0.3)), lineWidth: 1)
                x += spacing
            }
        }
    }
}

#Preview {
    WelcomeView(onComplete: {})
}
