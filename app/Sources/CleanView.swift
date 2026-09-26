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
            ZStack(alignment: .bottom) {
                AuroraBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        ForEach(Risk.allCases, id: \.self) { risk in
                            section(for: risk)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 120)
                }
                .refreshable { await store.scan() }

                cleanBar
            }
            .navigationTitle("Clean")
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

    private func section(for risk: Risk) -> some View {
        let categories = CleanCategory.all.filter { $0.risk == risk }
        let total = categories.compactMap { store.results[$0.id]?.bytes }.reduce(0, +)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: risk.title, trailing: Format.bytes(total))
            VStack(spacing: 0) {
                ForEach(categories) { category in
                    NavigationLink {
                        CategoryDetailView(category: category)
                    } label: {
                        CategoryRow(category: category)
                    }
                    .buttonStyle(.plain)
                    if category.id != categories.last?.id {
                        Divider().background(Color.white.opacity(0.08)).padding(.leading, 66)
                    }
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
        }
    }

    private var cleanBar: some View {
        Button {
            Haptics.tap()
            if confirmClean || includesPrivacy { confirming = true } else { startClean() }
        } label: {
            HStack {
                if store.isCleaning {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "sparkles")
                }
                store.isCleaning ? Text("Cleaning…") : Text("Clean \(Format.bytes(selectedBytes))")
            }
        }
        .buttonStyle(GlowButtonStyle(colors: includesPrivacy ? [Theme.pink, Theme.violet] : [Theme.violet, Theme.blue, Theme.cyan]))
        .disabled(store.selection.isEmpty || store.isCleaning || store.isScanning)
        .opacity(store.selection.isEmpty ? 0.5 : 1)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private func startClean() {
        Task { result = await store.clean(store.selection) }
    }
}

struct CategoryRow: View {
    @EnvironmentObject private var store: AppStore
    let category: CleanCategory

    private var isOn: Binding<Bool> {
        Binding(get: { store.selection.contains(category.id) },
                set: { on in
                    Haptics.tap()
                    if on { store.selection.insert(category.id) } else { store.selection.remove(category.id) }
                })
    }

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(symbol: category.icon, colors: category.colors)
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(category.title))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundColor(.white)
                Text(LocalizedStringKey(category.subtitle))
                    .font(.caption)
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                if store.isScanning && store.results[category.id] == nil {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Text(Format.bytes(store.results[category.id]?.bytes ?? 0))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundColor(.white)
                    Text("\(Int(store.results[category.id]?.files ?? 0)) files")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(Theme.secondaryText)
                }
            }
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(category.risk.tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct CategoryDetailView: View {
    @EnvironmentObject private var store: AppStore
    let category: CleanCategory

    private var result: CategoryResult? { store.results[category.id] }
    private var isAppList: Bool { category.id == "app_caches" }

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    GlassCard {
                        HStack(spacing: 16) {
                            IconBadge(symbol: category.icon, colors: category.colors, size: 52)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Format.bytes(result?.bytes ?? 0))
                                    .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                                Text(LocalizedStringKey(category.subtitle))
                                    .font(.footnote)
                                    .foregroundColor(Theme.secondaryText)
                            }
                        }
                    }

                    if isAppList && !store.exclusions.isEmpty {
                        Text("\(store.exclusions.count) apps are excluded and not shown.")
                            .font(.footnote)
                            .foregroundColor(Theme.secondaryText)
                            .padding(.horizontal, 4)
                    }

                    if let items = result?.items, !items.isEmpty {
                        SectionHeader(title: "Breakdown", trailing: "\(items.count)")
                        VStack(spacing: 0) {
                            ForEach(items) { item in
                                itemRow(item)
                                if item.id != items.last?.id {
                                    Divider().background(Color.white.opacity(0.08)).padding(.leading, 60)
                                }
                            }
                        }
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    } else {
                        GlassCard {
                            HStack {
                                Image(systemName: "checkmark.seal.fill").foregroundColor(Theme.mint)
                                Text("Nothing to clean here.")
                            }
                        }
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle(LocalizedStringKey(category.title))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func itemRow(_ item: ScanItem) -> some View {
        let share = (result?.bytes ?? 0) > 0 ? Double(item.bytes) / Double(result?.bytes ?? 1) : 0
        HStack(spacing: 12) {
            if isAppList, let icon = AppMeta.icon(for: item.name) {
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                IconBadge(symbol: category.icon, colors: category.colors, size: 34)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(isAppList ? AppMeta.name(for: item.name) : item.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(LinearGradient(colors: category.colors, startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4, geo.size.width * CGFloat(share)))
                    }
                }
                .frame(height: 5)
            }
            Text(Format.bytes(item.bytes))
                .font(.footnote.monospacedDigit())
                .foregroundColor(Theme.secondaryText)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contextMenu {
            if isAppList {
                Button {
                    store.toggleExclusion(item.name)
                    Task { await store.scan() }
                } label: {
                    Label(LocalizedStringKey(store.exclusions.contains(item.name) ? "Include again" : "Exclude from cleaning"),
                          systemImage: "hand.raised")
                }
            }
            Button {
                UIPasteboard.general.string = item.path
            } label: {
                Label("Copy path", systemImage: "doc.on.doc")
            }
        }
    }
}
