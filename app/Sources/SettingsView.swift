import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("confirmClean") private var confirmClean = true
    @AppStorage("haptics") private var haptics = true

    var body: some View {
        NavigationView {
            ZStack {
                AuroraBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        statsCard

                        SectionHeader(title: "Automation")
                        NavigationLink(isActive: $store.showSchedule) {
                            ScheduleView()
                        } label: {
                            settingsRow(icon: "calendar.badge.clock", colors: [Theme.teal, Theme.cyan],
                                        title: "Automatic cleaning",
                                        value: store.schedule.enabled
                                            ? String(localized: "Every \(store.schedule.hours) h")
                                            : String(localized: "Off"))
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            ExclusionsView()
                        } label: {
                            settingsRow(icon: "hand.raised.fill", colors: [Theme.pink, Theme.violet],
                                        title: "Excluded apps", value: "\(store.exclusions.count)")
                        }
                        .buttonStyle(.plain)

                        SectionHeader(title: "Behaviour")
                        GlassCard(padding: 16) {
                            VStack(spacing: 14) {
                                Toggle(isOn: $confirmClean) {
                                    Label("Confirm before cleaning", systemImage: "checkmark.shield")
                                }
                                Divider().background(Color.white.opacity(0.08))
                                Toggle(isOn: $haptics) {
                                    Label("Haptic feedback", systemImage: "hand.tap")
                                }
                            }
                            .tint(Theme.cyan)
                        }

                        SectionHeader(title: "History")
                        NavigationLink {
                            HistoryView()
                        } label: {
                            settingsRow(icon: "chart.bar.fill", colors: [Theme.violet, Theme.blue],
                                        title: "Cleaning history", value: "\(store.history.count)")
                        }
                        .buttonStyle(.plain)

                        SectionHeader(title: "About")
                        GlassCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                infoRow("Version", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                                infoRow("Jailbreak", store.helper.scheme)
                                infoRow("Jailbreak root", store.helper.jbroot.isEmpty ? "/" : store.helper.jbroot)
                                infoRow("Helper", store.helperAvailable ? String(localized: "Installed") : String(localized: "Missing"))
                                Text("Purify is a modern take on the classic iCleaner Pro idea, rebuilt for rootless and roothide.")
                                    .font(.caption)
                                    .foregroundColor(Theme.secondaryText)
                                    .padding(.top, 4)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Settings")
        }
        .navigationViewStyle(.stack)
        .onAppear { store.loadHistory() }
    }

    private var statsCard: some View {
        GlassCard {
            HStack(spacing: 16) {
                IconBadge(symbol: "leaf.fill", colors: [Theme.mint, Theme.teal], size: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Format.bytes(store.allTimeFreed))
                        .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.aiGradient)
                    Text("freed since you installed Purify")
                        .font(.footnote)
                        .foregroundColor(Theme.secondaryText)
                }
            }
        }
    }

    private func settingsRow(icon: String, colors: [Color], title: String, value: String) -> some View {
        GlassCard(padding: 14) {
            HStack(spacing: 14) {
                IconBadge(symbol: icon, colors: colors, size: 36)
                Text(LocalizedStringKey(title)).font(.system(.body, design: .rounded).weight(.semibold))
                Spacer()
                Text(value).foregroundColor(Theme.secondaryText)
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundColor(Theme.secondaryText)
            }
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(LocalizedStringKey(title)).foregroundColor(Theme.secondaryText)
            Spacer()
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .font(.subheadline)
    }
}

// MARK: - Schedule

struct ScheduleView: View {
    @EnvironmentObject private var store: AppStore
    @State private var enabled = false
    @State private var hours = 24
    @State private var categories: Set<String> = CleanCategory.defaultSelection
    @State private var saving = false

    private let intervals: [(Int, String)] = [(6, "6 hours"), (12, "12 hours"), (24, "Daily"), (72, "Every 3 days"), (168, "Weekly")]

    var body: some View {
        ZStack(alignment: .bottom) {
            AuroraBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    GlassCard(padding: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(isOn: $enabled.animation()) {
                                Label("Clean automatically", systemImage: "sparkles")
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                            }
                            .tint(Theme.cyan)
                            Text("A background launch daemon cleans quietly while you use your device. Privacy items can't be scheduled.")
                                .font(.caption)
                                .foregroundColor(Theme.secondaryText)
                        }
                    }

                    if enabled {
                        SectionHeader(title: "Interval")
                        Picker("Interval", selection: $hours) {
                            ForEach(intervals, id: \.0) { Text(LocalizedStringKey($0.1)).tag($0.0) }
                        }
                        .pickerStyle(.segmented)

                        SectionHeader(title: "What to clean")
                        VStack(spacing: 0) {
                            let schedulable = CleanCategory.all.filter { $0.risk != .privacy }
                            ForEach(schedulable) { category in
                                HStack(spacing: 12) {
                                    IconBadge(symbol: category.icon, colors: category.colors, size: 30)
                                    Text(LocalizedStringKey(category.title))
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { categories.contains(category.id) },
                                        set: { if $0 { categories.insert(category.id) } else { categories.remove(category.id) } }))
                                        .labelsHidden()
                                        .tint(Theme.mint)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                            }
                        }
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
                .padding(18)
                .padding(.bottom, 90)
            }

            Button {
                Task {
                    saving = true
                    await store.setSchedule(hours: enabled ? hours : nil, categories: categories)
                    saving = false
                }
            } label: {
                HStack {
                    if saving { ProgressView().tint(.white) }
                    Text("Save")
                }
            }
            .buttonStyle(GlowButtonStyle())
            .disabled(saving || (enabled && categories.isEmpty))
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .navigationTitle("Automatic cleaning")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.refreshSchedule()
            enabled = store.schedule.enabled
            if store.schedule.enabled {
                hours = store.schedule.hours
                categories = Set(store.schedule.categories)
            }
        }
    }
}

// MARK: - Exclusions

struct ExclusionsView: View {
    @EnvironmentObject private var store: AppStore

    private var candidates: [String] {
        (store.results["app_caches"]?.items.map(\.name) ?? []).filter { !store.exclusions.contains($0) }
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Excluded apps keep their caches and temporary files. Useful for apps that store offline content like music, podcasts or maps.")
                        .font(.footnote)
                        .foregroundColor(Theme.secondaryText)
                        .padding(.horizontal, 4)

                    if !store.exclusions.isEmpty {
                        SectionHeader(title: "Excluded")
                        appList(store.exclusions.sorted(), excluded: true)
                    }
                    if !candidates.isEmpty {
                        SectionHeader(title: "Apps with caches")
                        appList(candidates, excluded: false)
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("Excluded apps")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func appList(_ ids: [String], excluded: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(ids, id: \.self) { id in
                HStack(spacing: 12) {
                    if let icon = AppMeta.icon(for: id) {
                        Image(uiImage: icon).resizable().frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        IconBadge(symbol: "app.fill", size: 32)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppMeta.name(for: id)).font(.subheadline.weight(.semibold))
                        Text(id).font(.caption2.monospaced()).foregroundColor(Theme.secondaryText).lineLimit(1)
                    }
                    Spacer()
                    Button {
                        Haptics.tap()
                        withAnimation { store.toggleExclusion(id) }
                    } label: {
                        Image(systemName: excluded ? "minus.circle.fill" : "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(excluded ? Theme.pink : Theme.mint)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - History

struct HistoryView: View {
    @EnvironmentObject private var store: AppStore

    private var maxBytes: Int64 { max(store.history.prefix(14).map(\.bytes).max() ?? 1, 1) }

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if store.history.isEmpty {
                        GlassCard { Text("No cleans yet. Your first Smart Clean will show up here.").foregroundColor(Theme.secondaryText) }
                    } else {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Recent cleans").font(.headline)
                                HStack(alignment: .bottom, spacing: 6) {
                                    ForEach(Array(store.history.prefix(14).reversed())) { entry in
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(LinearGradient(colors: entry.auto ? [Theme.teal, Theme.mint] : [Theme.violet, Theme.cyan],
                                                                 startPoint: .bottom, endPoint: .top))
                                            .frame(height: max(6, 110 * CGFloat(Double(entry.bytes) / Double(maxBytes))))
                                    }
                                }
                                .frame(height: 110, alignment: .bottom)
                                HStack(spacing: 14) {
                                    LegendDot(color: Theme.violet, title: "Manual")
                                    LegendDot(color: Theme.teal, title: "Automatic")
                                }
                            }
                        }

                        VStack(spacing: 0) {
                            ForEach(store.history) { entry in
                                HStack(spacing: 12) {
                                    Image(systemName: entry.auto ? "clock.arrow.circlepath" : "sparkles")
                                        .foregroundColor(entry.auto ? Theme.teal : Theme.violet)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(Format.date(entry.date)).font(.subheadline.weight(.semibold))
                                        Text("\(Int(entry.files)) files · \(entry.categories.count) categories")
                                            .font(.caption)
                                            .foregroundColor(Theme.secondaryText)
                                    }
                                    Spacer()
                                    Text(Format.bytes(entry.bytes)).font(.footnote.monospacedDigit().weight(.semibold))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                            }
                        }
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("Cleaning history")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LegendDot: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(LocalizedStringKey(title)).font(.caption).foregroundColor(Theme.secondaryText)
        }
    }
}
