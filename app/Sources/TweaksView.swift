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
            ZStack(alignment: .bottom) {
                AuroraBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        summary
                        Picker("Filter", selection: $filter) {
                            ForEach(Filter.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        if loading && tweaks.isEmpty {
                            ProgressView().padding(40)
                        } else if visible.isEmpty {
                            GlassCard {
                                Text(tweaks.isEmpty ? "No tweaks installed." : "No tweaks match your search.")
                                    .foregroundColor(Theme.secondaryText)
                            }
                        } else {
                            VStack(spacing: 0) {
                                ForEach(visible) { tweak in
                                    TweakRow(tweak: tweak) { enabled in
                                        Task { await set([tweak.name], enabled: enabled) }
                                    }
                                    if tweak.id != visible.last?.id {
                                        Divider().background(Color.white.opacity(0.08)).padding(.leading, 66)
                                    }
                                }
                            }
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, pendingRespring ? 100 : 24)
                }
                .refreshable { await load() }

                if pendingRespring {
                    Button {
                        Task { await store.power("respring") }
                    } label: {
                        Label("Respring to apply", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(GlowButtonStyle(colors: [Theme.pink, Theme.violet]))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Tweaks")
            .searchable(text: $query, prompt: Text("Search tweaks, packages, apps"))
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
        }
        .navigationViewStyle(.stack)
        .task { await load() }
        .confirmationDialog("Disable every tweak?", isPresented: $confirmDisableAll, titleVisibility: .visible) {
            Button("Disable all", role: .destructive) { Task { await disableAll() } }
        } message: {
            Text("Handy to find a misbehaving tweak. Purify remembers what was enabled so you can restore it with one tap.")
        }
    }

    private var summary: some View {
        let enabled = tweaks.filter(\.enabled).count
        return HStack(spacing: 12) {
            StatPill(value: "\(tweaks.count)", label: "installed", color: Theme.cyan)
            StatPill(value: "\(enabled)", label: "active", color: Theme.mint)
            StatPill(value: "\(tweaks.count - enabled)", label: "disabled", color: Theme.pink)
        }
        .padding(.top, 4)
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
            withAnimation(.spring()) { pendingRespring = true }
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

struct StatPill: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundColor(color)
            Text(LocalizedStringKey(label))
                .font(.caption)
                .foregroundColor(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

    private var colors: [Color] {
        let palette: [[Color]] = [[Theme.violet, Theme.indigo], [Theme.cyan, Theme.blue], [Theme.pink, Theme.violet],
                                  [Theme.teal, Theme.mint], [Theme.orange, Theme.pink], [Theme.amber, Theme.orange]]
        let hash = tweak.name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[hash % palette.count]
    }

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(symbol: "puzzlepiece.fill", colors: tweak.enabled ? colors : [.gray, .gray.opacity(0.6)])
            VStack(alignment: .leading, spacing: 3) {
                Text(tweak.name)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundColor(tweak.enabled ? .white : Theme.secondaryText)
                    .lineLimit(1)
                Text(targets)
                    .font(.caption)
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
                if let package = tweak.package {
                    Text(package)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(Theme.secondaryText.opacity(0.7))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Toggle("", isOn: Binding(get: { tweak.enabled }, set: { onToggle($0) }))
                .labelsHidden()
                .tint(Theme.mint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
