import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var result: CleanResponse?

    private var busy: Bool { store.isScanning || store.isCleaning }

    var body: some View {
        NavigationView {
            List {
                if !store.helperAvailable {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Helper not found").font(.headline)
                                Text("Purify needs its root helper. Install the package through Sileo or Zebra instead of sideloading the .app.")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Theme.orange)
                        }
                    }
                }

                Section { overview }

                Section {
                    assistant
                    ForEach(store.analysis.insights) { insight in
                        InsightRow(insight: insight)
                    }
                } header: {
                    Text("Assistant")
                }

                Section {
                    actionRow("Respring", icon: "arrow.clockwise", color: Theme.indigo) {
                        Task { await store.power("respring") }
                    }
                    actionRow("Refresh icons", icon: "square.grid.3x3.fill", color: Theme.teal) {
                        Task {
                            await store.power("uicache")
                            store.show(String(localized: "Icon cache rebuilt"))
                        }
                    }
                    Button {
                        store.tab = .tools
                        store.toolRoute = .largeFiles
                    } label: {
                        rowLabel("Large files", icon: "doc.viewfinder.fill", color: Theme.orange, chevron: true)
                    }
                } header: {
                    Text("Quick actions")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Purify")
            .refreshable { await store.scan() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Text(store.helper.scheme)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(.tertiarySystemFill)))
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(item: $result) { CleanResultView(response: $0) }
    }

    // MARK: - Overview

    private var overview: some View {
        let storage = store.storage
        let reclaim = min(store.analysis.safeBytes, storage.used)
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reclaimable")
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(busy && store.results.isEmpty ? "–" : Format.bytes(store.analysis.safeBytes))
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    Spacer()
                    if busy {
                        ProgressView()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                StorageBar(segments: [
                    BarSegment(value: Double(storage.used - reclaim), color: Theme.accent),
                    BarSegment(value: Double(reclaim), color: Theme.orange),
                ])
                HStack(spacing: 14) {
                    LegendDot(color: Theme.accent, title: "Used")
                    LegendDot(color: Theme.orange, title: "Reclaimable")
                    Spacer()
                    Text("\(Format.bytes(storage.free)) free")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    Task { await store.scan() }
                } label: {
                    Label("Scan", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    Haptics.tap()
                    Task { result = await store.smartClean() }
                } label: {
                    Label("Smart Clean", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.helperAvailable)
            }
            .controlSize(.large)
            .disabled(busy)
        }
        .padding(.vertical, 6)
    }

    private var assistant: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Purify Intelligence", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.accent)
                Text(store.analysis.summary)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            VStack(spacing: 3) {
                ScoreRing(score: store.analysis.score).frame(width: 40, height: 40)
                Text("Health").font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Rows

    private func actionRow(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            rowLabel(title, icon: icon, color: color, chevron: false)
        }
    }

    private func rowLabel(_ title: String, icon: String, color: Color, chevron: Bool) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: icon, colors: [color])
            Text(LocalizedStringKey(title)).foregroundColor(.primary)
            Spacer()
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Color(.tertiaryLabel))
            }
        }
    }
}

extension CleanResponse: Identifiable {
    var id: String { "\(freed)-\(files)-\(errors)" }
}

struct InsightRow: View {
    @EnvironmentObject private var store: AppStore
    let insight: Insight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(insight.tint)
                .frame(width: 29, height: 29)
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title).font(.subheadline.weight(.semibold))
                Text(insight.detail)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let action = insight.action, let title = insight.actionTitle {
                    Button(title) {
                        Haptics.tap()
                        Task { await store.handle(action) }
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
                    .padding(.top, 2)
                    .disabled(store.isCleaning || store.isScanning)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct CleanResultView: View {
    @Environment(\.dismiss) private var dismiss
    let response: CleanResponse
    @State private var appear = false

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(Theme.mint)
                .scaleEffect(appear ? 1 : 0.5)
                .opacity(appear ? 1 : 0)
            Text(Format.bytes(response.freed))
                .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
            Text("freed · \(Int(response.files)) files removed")
                .foregroundColor(.secondary)
            if response.errors > 0 {
                Text("\(Int(response.errors)) items were in use and skipped")
                    .font(.footnote)
                    .foregroundColor(Theme.orange)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { appear = true }
        }
    }
}
