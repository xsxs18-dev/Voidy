import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var result: CleanResponse?

    var body: some View {
        NavigationView {
            ZStack {
                AuroraBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        header
                        if !store.helperAvailable { helperMissing }
                        orbCard
                        assistantCard
                        ForEach(store.analysis.insights) { insight in
                            InsightCard(insight: insight)
                        }
                        storageCard
                        quickActions
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 30)
                }
                .refreshable { await store.scan() }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .sheet(item: $result) { response in
            CleanResultView(response: response)
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Purify")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.aiGradient)
                Text("Smart cleaner for your jailbreak")
                    .font(.subheadline)
                    .foregroundColor(Theme.secondaryText)
            }
            Spacer()
            Text(store.helper.scheme)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .overlay(Capsule().strokeBorder(Theme.cyan.opacity(0.4)))
        }
        .padding(.top, 12)
    }

    private var helperMissing: some View {
        GlassCard {
            HStack(spacing: 14) {
                IconBadge(symbol: "exclamationmark.triangle.fill", colors: [Theme.pink, Theme.orange])
                VStack(alignment: .leading, spacing: 4) {
                    Text("Helper not found").font(.headline)
                    Text("Purify needs its root helper. Install the package through Sileo or Zebra instead of sideloading the .app.")
                        .font(.footnote)
                        .foregroundColor(Theme.secondaryText)
                }
            }
        }
    }

    private var orbCard: some View {
        GlassCard(padding: 22) {
            VStack(spacing: 20) {
                ZStack {
                    AIOrb(active: store.isScanning || store.isCleaning, size: 190)
                    VStack(spacing: 4) {
                        if store.isScanning || store.isCleaning {
                            ProgressView().tint(.white)
                            Text(store.isCleaning ? "Cleaning…" : "Analyzing…")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundColor(Theme.secondaryText)
                        } else {
                            Text(Format.bytes(store.analysis.safeBytes))
                                .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundColor(.white)
                            Text("reclaimable")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundColor(Theme.secondaryText)
                        }
                    }
                }
                .frame(height: 210)

                HStack(spacing: 12) {
                    Button {
                        Haptics.tap()
                        Task { await store.scan() }
                    } label: {
                        Label("Scan", systemImage: "viewfinder")
                    }
                    .buttonStyle(PillButtonStyle(tint: Theme.cyan))
                    .disabled(store.isScanning || store.isCleaning)

                    Button {
                        Haptics.tap()
                        Task { result = await store.smartClean() }
                    } label: {
                        Label("Smart Clean", systemImage: "sparkles")
                    }
                    .buttonStyle(GlowButtonStyle())
                    .disabled(store.isScanning || store.isCleaning || !store.helperAvailable)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var assistantCard: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Theme.aiGradient)
                        Text("Purify Intelligence")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(Theme.aiGradient)
                    }
                    TypewriterText(text: store.analysis.summary)
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                VStack(spacing: 4) {
                    ScoreRing(score: store.analysis.score)
                        .frame(width: 54, height: 54)
                    Text("Health")
                        .font(.caption2)
                        .foregroundColor(Theme.secondaryText)
                }
            }
        }
    }

    private var storageCard: some View {
        let storage = store.storage
        let reclaim = min(store.analysis.safeBytes, storage.used)
        return GlassCard {
            HStack(spacing: 20) {
                ZStack {
                    RingChart(segments: [
                        RingSegment(value: Double(storage.used - reclaim), color: Theme.violet),
                        RingSegment(value: Double(reclaim), color: Theme.cyan),
                        RingSegment(value: Double(storage.free), color: Color.white.opacity(0.12)),
                    ], lineWidth: 14)
                    VStack(spacing: 0) {
                        Text("\(Int((1 - storage.freeRatio) * 100))%")
                            .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                        Text("used").font(.caption2).foregroundColor(Theme.secondaryText)
                    }
                }
                .frame(width: 110, height: 110)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Storage").font(.headline)
                    LegendRow(color: Theme.violet, title: "Used", value: Format.bytes(storage.used))
                    LegendRow(color: Theme.cyan, title: "Reclaimable", value: Format.bytes(reclaim))
                    LegendRow(color: .white.opacity(0.3), title: "Free", value: Format.bytes(storage.free))
                }
            }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Quick actions")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                QuickTile(title: "Respring", icon: "arrow.clockwise", colors: [Theme.violet, Theme.indigo]) {
                    Task { await store.power("respring") }
                }
                QuickTile(title: "Refresh icons", icon: "square.grid.3x3.fill", colors: [Theme.teal, Theme.cyan]) {
                    Task {
                        await store.power("uicache")
                        store.show(String(localized: "Icon cache rebuilt"))
                    }
                }
                QuickTile(title: "Tweaks", icon: "puzzlepiece.extension.fill", colors: [Theme.pink, Theme.violet]) {
                    store.tab = .tweaks
                }
                QuickTile(title: "Large files", icon: "doc.viewfinder.fill", colors: [Theme.amber, Theme.orange]) {
                    store.tab = .tools
                    store.toolRoute = .largeFiles
                }
            }
        }
    }
}

extension CleanResponse: Identifiable {
    var id: String { "\(freed)-\(files)-\(errors)" }
}

// MARK: - Components

struct LegendRow: View {
    let color: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(LocalizedStringKey(title)).font(.subheadline).foregroundColor(Theme.secondaryText)
            Spacer()
            Text(value).font(.subheadline.monospacedDigit())
        }
    }
}

struct QuickTile: View {
    let title: String
    let icon: String
    let colors: [Color]
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 12) {
                IconBadge(symbol: icon, colors: colors, size: 34)
                Text(LocalizedStringKey(title))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

struct InsightCard: View {
    @EnvironmentObject private var store: AppStore
    let insight: Insight

    var body: some View {
        GlassCard(padding: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: insight.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(insight.tint)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(insight.tint.opacity(0.15)))
                VStack(alignment: .leading, spacing: 6) {
                    Text(insight.title).font(.system(.headline, design: .rounded))
                    Text(insight.detail)
                        .font(.footnote)
                        .foregroundColor(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let action = insight.action, let title = insight.actionTitle {
                        Button(title) {
                            Haptics.tap()
                            Task { await store.handle(action) }
                        }
                        .buttonStyle(PillButtonStyle(tint: insight.tint))
                        .padding(.top, 4)
                        .disabled(store.isCleaning || store.isScanning)
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

struct CleanResultView: View {
    @Environment(\.dismiss) private var dismiss
    let response: CleanResponse
    @State private var appear = false

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 22) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(Theme.aiAngular)
                        .frame(width: 150, height: 150)
                        .blur(radius: 30)
                        .opacity(appear ? 0.8 : 0)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 96, weight: .semibold))
                        .foregroundStyle(.white, Theme.aiGradient)
                        .scaleEffect(appear ? 1 : 0.3)
                }
                Text(Format.bytes(response.freed))
                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.aiGradient)
                Text("freed · \(Int(response.files)) files removed")
                    .foregroundColor(Theme.secondaryText)
                if response.errors > 0 {
                    Text("\(Int(response.errors)) items were in use and skipped")
                        .font(.footnote)
                        .foregroundColor(Theme.amber)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(GlowButtonStyle())
                    .padding(.horizontal, 30)
                    .padding(.bottom, 20)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) { appear = true }
        }
    }
}
