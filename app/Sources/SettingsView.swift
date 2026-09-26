import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("confirmClean") private var confirmClean = true
    @AppStorage("haptics") private var haptics = true

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack(spacing: 14) {
                        IconBadge(symbol: "leaf.fill", colors: [Theme.mint], size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Format.bytes(store.allTimeFreed))
                                .font(.title2.weight(.bold).monospacedDigit())
                            Text("freed since you installed Voidly")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    NavigationLink(isActive: $store.showSchedule) {
                        ScheduleView()
                    } label: {
                        row("Automatic cleaning", icon: "clock.arrow.circlepath", color: Theme.teal,
                            value: store.schedule.enabled
                                ? String(localized: "Every \(store.schedule.hours) h")
                                : String(localized: "Off"))
                    }
                    NavigationLink {
                        ExclusionsView()
                    } label: {
                        row("Excluded apps", icon: "hand.raised.fill", color: Theme.orange, value: "\(store.exclusions.count)")
                    }
                } header: {
                    Text("Automation")
                }

                Section {
                    Toggle(isOn: $confirmClean) {
                        row("Confirm before cleaning", icon: "checkmark.shield.fill", color: Theme.blue, value: nil)
                    }
                    Toggle(isOn: $haptics) {
                        row("Haptic feedback", icon: "hand.tap.fill", color: Theme.pink, value: nil)
                    }
                } header: {
                    Text("Behaviour")
                }

                Section {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        row("Cleaning history", icon: "chart.bar.fill", color: Theme.indigo, value: "\(store.history.count)")
                    }
                }

                Section {
                    info("Version", version)
                    info("Jailbreak", store.helper.scheme)
                    info("Jailbreak root", store.helper.jbroot.isEmpty ? "/" : store.helper.jbroot)
                    info("Helper", store.helperAvailable ? String(localized: "Installed") : String(localized: "Missing"))
                } header: {
                    Text("About")
                } footer: {
                    Text("A lightweight system cleaner for rootless and roothide jailbreaks.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
        }
        .navigationViewStyle(.stack)
        .onAppear { store.loadHistory() }
    }

    private func row(_ title: String, icon: String, color: Color, value: String?) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: icon, colors: [color])
            Text(LocalizedStringKey(title))
            if let value = value {
                Spacer()
                Text(value).foregroundColor(.secondary)
            }
        }
    }

    private func info(_ title: String, _ value: String) -> some View {
        HStack {
            Text(LocalizedStringKey(title))
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .contextMenu {
            Button { UIPasteboard.general.string = value } label: { Label("Copy", systemImage: "doc.on.doc") }
        }
    }
}

// MARK: - Schedule

struct ScheduleView: View {
    @EnvironmentObject private var store: AppStore
    @State private var enabled = false
    @State private var hours = 24
    @State private var categories: Set<String> = CleanCategory.defaultSelection
    @State private var saving = false

    private let intervals: [(Int, String)] = [(6, "Every 6 hours"), (12, "Every 12 hours"), (24, "Daily"),
                                              (72, "Every 3 days"), (168, "Weekly")]

    var body: some View {
        List {
            Section {
                Toggle("Clean automatically", isOn: $enabled.animation())
            } footer: {
                Text("A background launch daemon cleans quietly while you use your device. Privacy items can't be scheduled.")
            }

            if enabled {
                Section {
                    Picker("Interval", selection: $hours) {
                        ForEach(intervals, id: \.0) { Text(LocalizedStringKey($0.1)).tag($0.0) }
                    }
                }

                Section {
                    ForEach(CleanCategory.all.filter { $0.risk != .privacy }) { category in
                        Toggle(isOn: Binding(
                            get: { categories.contains(category.id) },
                            set: { if $0 { categories.insert(category.id) } else { categories.remove(category.id) } })) {
                            HStack(spacing: 12) {
                                IconBadge(symbol: category.icon, colors: category.colors)
                                Text(LocalizedStringKey(category.title))
                            }
                        }
                    }
                } header: {
                    Text("What to clean")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Automatic cleaning")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if saving {
                    ProgressView()
                } else {
                    Button("Save") {
                        Task {
                            saving = true
                            await store.setSchedule(hours: enabled ? hours : nil, categories: categories)
                            saving = false
                        }
                    }
                    .font(.body.weight(.semibold))
                    .disabled(enabled && categories.isEmpty)
                }
            }
        }
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
        List {
            Section {
                if store.exclusions.isEmpty {
                    Text("No apps excluded.").foregroundColor(.secondary)
                } else {
                    ForEach(store.exclusions.sorted(), id: \.self) { id in
                        appRow(id, excluded: true)
                    }
                }
            } header: {
                Text("Excluded")
            } footer: {
                Text("Excluded apps keep their caches and temporary files. Useful for apps that store offline content like music, podcasts or maps.")
            }

            if !candidates.isEmpty {
                Section {
                    ForEach(candidates, id: \.self) { id in
                        appRow(id, excluded: false)
                    }
                } header: {
                    Text("Apps with caches")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Excluded apps")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func appRow(_ id: String, excluded: Bool) -> some View {
        HStack(spacing: 12) {
            AppIconView(bundleID: id)
            VStack(alignment: .leading, spacing: 1) {
                Text(AppMeta.name(for: id))
                Text(id).font(.caption2).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            Button {
                Haptics.tap()
                withAnimation { store.toggleExclusion(id) }
            } label: {
                Image(systemName: excluded ? "minus.circle.fill" : "plus.circle.fill")
                    .font(.title3)
                    .foregroundColor(excluded ? Theme.red : Theme.mint)
            }
            .buttonStyle(.borderless)
        }
    }
}

// MARK: - History

struct HistoryView: View {
    @EnvironmentObject private var store: AppStore

    private var recent: [HistoryEntry] { Array(store.history.prefix(14).reversed()) }
    private var maxBytes: Int64 { max(recent.map(\.bytes).max() ?? 1, 1) }

    var body: some View {
        List {
            if store.history.isEmpty {
                Section {
                    Text("No cleans yet. Your first Smart Clean will show up here.").foregroundColor(.secondary)
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .bottom, spacing: 5) {
                            ForEach(recent) { entry in
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(entry.auto ? Theme.teal : Theme.accent)
                                    .frame(height: max(4, 90 * CGFloat(Double(entry.bytes) / Double(maxBytes))))
                            }
                        }
                        .frame(height: 90, alignment: .bottom)
                        HStack(spacing: 14) {
                            LegendDot(color: Theme.accent, title: "Manual")
                            LegendDot(color: Theme.teal, title: "Automatic")
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Recent cleans")
                }

                Section {
                    ForEach(store.history) { entry in
                        HStack(spacing: 12) {
                            Image(systemName: entry.auto ? "clock.arrow.circlepath" : "sparkles")
                                .foregroundColor(entry.auto ? Theme.teal : Theme.accent)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Format.date(entry.date))
                                Text("\(Int(entry.files)) files · \(entry.categories.count) categories")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            SizeLabel(bytes: entry.bytes)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Cleaning history")
        .navigationBarTitleDisplayMode(.inline)
    }
}
