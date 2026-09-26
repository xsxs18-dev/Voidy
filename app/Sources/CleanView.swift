import SwiftUI
import UIKit

struct CleanView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("confirmClean") private var confirmClean = true
    @State private var confirming = false
    @State private var result: CleanResponse?

    private var selectedBytes: Int64 { store.bytes(for: store.selection) }
    private var includesPrivacy: Bool {
        store.selection.contains { CleanCategory.named($0)?.risk == .privacy }
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(Risk.allCases, id: \.self) { risk in
                    let categories = CleanCategory.all.filter { $0.risk == risk }
                    Section {
                        ForEach(categories) { category in
                            NavigationLink {
                                CategoryDetailView(category: category)
                            } label: {
                                CategoryRow(category: category)
                            }
                        }
                    } header: {
                        Text(LocalizedStringKey(risk.title))
                    } footer: {
                        if risk == .privacy {
                            Text("Privacy items are never cleaned automatically.")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Clean")
            .refreshable { await store.scan() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { store.selection = CleanCategory.defaultSelection } label: {
                            Label("Recommended only", systemImage: "checkmark.seal")
                        }
                        Button { store.selection = Set(CleanCategory.all.map(\.id)) } label: {
                            Label("Select all", systemImage: "checklist")
                        }
                        Button { store.selection = [] } label: {
                            Label("Select none", systemImage: "circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                BottomActionBar(role: includesPrivacy ? .destructive : nil,
                                disabled: store.selection.isEmpty || store.isCleaning || store.isScanning) {
                    Haptics.tap()
                    if confirmClean || includesPrivacy { confirming = true } else { startClean() }
                } label: {
                    HStack(spacing: 8) {
                        if store.isCleaning { ProgressView() }
                        store.isCleaning ? Text("Cleaning…") : Text("Clean \(Format.bytes(selectedBytes))")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(item: $result) { CleanResultView(response: $0) }
        .confirmationDialog("Clean \(Format.bytes(selectedBytes))?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Clean", role: .destructive) { startClean() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(LocalizedStringKey(includesPrivacy
                 ? "Privacy items are included: you will be signed out of websites and lose browsing history."
                 : "Only cache and temporary data will be removed."))
        }
    }

    private func startClean() {
        Task { result = await store.clean(store.selection) }
    }
}

struct CategoryRow: View {
    @EnvironmentObject private var store: AppStore
    let category: CleanCategory

    private var selected: Bool { store.selection.contains(category.id) }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.tap()
                if selected { store.selection.remove(category.id) } else { store.selection.insert(category.id) }
            } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(selected ? Theme.accent : Color(.tertiaryLabel))
            }
            .buttonStyle(.borderless)

            IconBadge(symbol: category.icon, colors: category.colors)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(category.title))
                Text(LocalizedStringKey(category.subtitle))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if store.isScanning && store.results[category.id] == nil {
                ProgressView()
            } else {
                SizeLabel(bytes: store.results[category.id]?.bytes ?? 0)
            }
        }
    }
}

struct CategoryDetailView: View {
    @EnvironmentObject private var store: AppStore
    let category: CleanCategory

    private var result: CategoryResult? { store.results[category.id] }
    private var isAppList: Bool { category.id == "app_caches" }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    IconBadge(symbol: category.icon, colors: category.colors, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Format.bytes(result?.bytes ?? 0))
                            .font(.title2.weight(.bold).monospacedDigit())
                        Text("\(Int(result?.files ?? 0)) files")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                Text(LocalizedStringKey(category.subtitle))
            }

            if let items = result?.items, !items.isEmpty {
                Section {
                    ForEach(items) { item in
                        itemRow(item)
                    }
                } header: {
                    Text("Breakdown")
                } footer: {
                    if isAppList {
                        store.exclusions.isEmpty
                            ? Text("Swipe left on an app to exclude it from cleaning.")
                            : Text("\(store.exclusions.count) apps are excluded and not shown.")
                    }
                }
            } else {
                Section {
                    Label("Nothing to clean here.", systemImage: "checkmark.circle")
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(LocalizedStringKey(category.title))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func itemRow(_ item: ScanItem) -> some View {
        HStack(spacing: 12) {
            if isAppList {
                AppIconView(bundleID: item.name)
            } else {
                IconBadge(symbol: category.icon, colors: category.colors)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(isAppList ? AppMeta.name(for: item.name) : item.name).lineLimit(1)
                if isAppList {
                    Text(item.name)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            SizeLabel(bytes: item.bytes)
        }
        .swipeActions(edge: .trailing) {
            if isAppList {
                Button {
                    store.toggleExclusion(item.name)
                    Task { await store.scan() }
                } label: {
                    Label("Exclude", systemImage: "hand.raised")
                }
                .tint(Theme.orange)
            }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = item.path
            } label: {
                Label("Copy path", systemImage: "doc.on.doc")
            }
        }
    }
}
