import SwiftUI

struct TweaksView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", enabled = "Enabled", disabled = "Disabled"
        var id: String { rawValue }
    }

    @EnvironmentObject private var store: AppStore
    @State private var tweaks: [TweakInfo] = []
    @State private var loading = false
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var pendingRespring = false
    @State private var confirmDisableAll = false

    private let snapshotKey = "tweakSnapshot"

    private var visible: [TweakInfo] {
        tweaks.filter { tweak in
            switch filter {
            case .all: break
            case .enabled: if !tweak.enabled { return false }
            case .disabled: if tweak.enabled { return false }
            }
            guard !query.isEmpty else { return true }
            return tweak.name.localizedCaseInsensitiveContains(query)
                || (tweak.package ?? "").localizedCaseInsensitiveContains(query)
                || tweak.filters.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    Picker("Filter", selection: $filter) {
                        ForEach(Filter.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    if loading && tweaks.isEmpty {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if visible.isEmpty {
                        Text(tweaks.isEmpty ? "No tweaks installed." : "No tweaks match your search.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(visible) { tweak in
                            TweakRow(tweak: tweak) { enabled in
                                Task { await set([tweak.name], enabled: enabled) }
                            }
                        }
                    }
                } header: {
                    Text("\(tweaks.filter(\.enabled).count) of \(tweaks.count) active")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Tweaks")
            .searchable(text: $query, prompt: Text("Search tweaks, packages, apps"))
            .refreshable { await load() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(role: .destructive) { confirmDisableAll = true } label: {
                            Label("Disable all (troubleshoot)", systemImage: "power")
                        }
                        Button { Task { await restoreSnapshot() } } label: {
                            Label("Restore previous state", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(UserDefaults.standard.stringArray(forKey: snapshotKey) == nil)
                        Divider()
                        Button { Task { await store.power("respring") } } label: {
                            Label("Respring", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if pendingRespring {
                    BottomActionBar(action: { Task { await store.power("respring") } }) {
                        Label("Respring to apply", systemImage: "arrow.clockwise")
                    }
                    .transition(.move(edge: .bottom))
                }
            }
        }
        .navigationViewStyle(.stack)
        .task { await load() }
        .confirmationDialog("Disable every tweak?", isPresented: $confirmDisableAll, titleVisibility: .visible) {
            Button("Disable all", role: .destructive) { Task { await disableAll() } }
        } message: {
            Text("Handy to find a misbehaving tweak. Purify remembers what was enabled so you can restore it with one tap.")
        }
    }

    // MARK: - Actions

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let list = try await store.helper.call(TweakList.self, ["tweaks", "list"])
            withAnimation { tweaks = list.tweaks }
        } catch {
            store.report(error)
        }
    }

    private func set(_ names: [String], enabled: Bool) async {
        guard !names.isEmpty else { return }
        do {
            try await store.helper.perform(["tweaks", "set", enabled ? "on" : "off"] + names)
            withAnimation { pendingRespring = true }
            Haptics.tap()
        } catch {
            store.report(error)
        }
        await load()
    }

    private func disableAll() async {
        let active = tweaks.filter(\.enabled).map(\.name)
        UserDefaults.standard.set(active, forKey: snapshotKey)
        await set(active, enabled: false)
        store.show(String(localized: "\(active.count) tweaks disabled"))
    }

    private func restoreSnapshot() async {
        guard let names = UserDefaults.standard.stringArray(forKey: snapshotKey) else { return }
        await set(names, enabled: true)
        UserDefaults.standard.removeObject(forKey: snapshotKey)
        store.show(String(localized: "Previous tweak state restored"))
    }
}

struct TweakRow: View {
    let tweak: TweakInfo
    let onToggle: (Bool) -> Void

    private var targets: String {
        let names = tweak.filters.map { AppMeta.name(for: $0) } + tweak.executables
        if names.isEmpty { return String(localized: "No filter") }
        if names.count <= 2 { return names.joined(separator: ", ") }
        return String(localized: "\(names.prefix(2).joined(separator: ", ")) +\(names.count - 2) more")
    }

    private var color: Color {
        let palette: [Color] = [Theme.indigo, Theme.blue, Theme.teal, Theme.mint, Theme.orange, Theme.pink, Theme.violet]
        let hash = tweak.name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[hash % palette.count]
    }

    var body: some View {
        Toggle(isOn: Binding(get: { tweak.enabled }, set: { onToggle($0) })) {
            HStack(spacing: 12) {
                IconBadge(symbol: "puzzlepiece.fill", colors: [tweak.enabled ? color : Theme.gray])
                VStack(alignment: .leading, spacing: 2) {
                    Text(tweak.name.trimmingCharacters(in: .whitespaces))
                        .foregroundColor(tweak.enabled ? .primary : .secondary)
                        .lineLimit(1)
                    Text(tweak.package.map { "\($0) · \(targets)" } ?? targets)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
