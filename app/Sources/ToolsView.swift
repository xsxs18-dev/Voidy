import SwiftUI
import UIKit

struct ToolsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var powerAction: PowerAction?

    enum PowerAction: String, Identifiable {
        case respring, uicache, userspace, reboot, ldrestart
        var id: String { rawValue }

        var title: String {
            switch self {
            case .respring: return "Respring"
            case .uicache: return "Rebuild icon cache"
            case .userspace: return "Userspace reboot"
            case .reboot: return "Reboot"
            case .ldrestart: return "Restart daemons (ldrestart)"
            }
        }

        var icon: String {
            switch self {
            case .respring: return "arrow.clockwise"
            case .uicache: return "square.grid.3x3.fill"
            case .userspace: return "arrow.triangle.2.circlepath"
            case .reboot: return "power"
            case .ldrestart: return "gearshape.2.fill"
            }
        }

        var colors: [Color] {
            switch self {
            case .respring: return [Theme.violet, Theme.indigo]
            case .uicache: return [Theme.teal, Theme.cyan]
            case .userspace: return [Theme.blue, Theme.violet]
            case .reboot: return [Theme.pink, Theme.orange]
            case .ldrestart: return [Theme.amber, Theme.orange]
            }
        }

        var warning: String {
            switch self {
            case .reboot: return "Rebooting leaves the jailbroken state. You will need to re-jailbreak afterwards."
            case .userspace: return "Restarts everything above the kernel. The jailbreak stays active."
            default: return "Open apps will be closed."
            }
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AuroraBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        SectionHeader(title: "Storage & packages")
                        VStack(spacing: 12) {
                            toolLink(.largeFiles, title: "Large files", subtitle: "Find what's eating your storage",
                                     icon: "doc.viewfinder.fill", colors: [Theme.amber, Theme.orange]) { LargeFilesView() }
                            toolLink(.orphans, title: "Orphaned packages", subtitle: "Dependencies nothing needs anymore",
                                     icon: "shippingbox.and.arrow.backward.fill", colors: [Theme.orange, Theme.pink]) { OrphansView() }
                            toolLink(.languages, title: "Unused languages", subtitle: "Localizations in jailbreak apps & tweaks",
                                     icon: "character.bubble.fill", colors: [Theme.teal, Theme.mint]) { LanguagesView() }
                            toolLink(.daemons, title: "Launch daemons", subtitle: "Start or stop jailbreak background services",
                                     icon: "gearshape.2.fill", colors: [Theme.blue, Theme.indigo]) { DaemonsView() }
                        }

                        SectionHeader(title: "Power")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach([PowerAction.respring, .uicache, .userspace, .ldrestart, .reboot]) { action in
                                QuickTile(title: action.title, icon: action.icon, colors: action.colors) {
                                    powerAction = action
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Tools")
        }
        .navigationViewStyle(.stack)
        .confirmationDialog(Text(LocalizedStringKey(powerAction?.title ?? "")),
                            isPresented: Binding(get: { powerAction != nil }, set: { if !$0 { powerAction = nil } }),
                            titleVisibility: .visible,
                            presenting: powerAction) { action in
            Button(LocalizedStringKey(action.title), role: .destructive) {
                Task { await store.power(action.rawValue) }
            }
        } message: { action in
            Text(LocalizedStringKey(action.warning))
        }
    }

    private func toolLink<Destination: View>(_ route: ToolRoute, title: String, subtitle: String, icon: String,
                                             colors: [Color], @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(tag: route, selection: $store.toolRoute, destination: destination) {
            GlassCard(padding: 14) {
                HStack(spacing: 14) {
                    IconBadge(symbol: icon, colors: colors, size: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(LocalizedStringKey(title))
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundColor(.white)
                        Text(LocalizedStringKey(subtitle))
                            .font(.caption)
                            .foregroundColor(Theme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundColor(Theme.secondaryText)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Large files

struct LargeFilesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var files: [LargeFile] = []
    @State private var loading = false
    @State private var threshold: Int64 = 100
    @State private var pendingDelete: LargeFile?

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    Picker("Minimum size", selection: $threshold) {
                        Text("50 MB").tag(Int64(50))
                        Text("100 MB").tag(Int64(100))
                        Text("250 MB").tag(Int64(250))
                        Text("1 GB").tag(Int64(1024))
                    }
                    .pickerStyle(.segmented)

                    if loading {
                        VStack(spacing: 12) {
                            AIOrb(active: true, size: 90)
                            Text("Searching your storage…").foregroundColor(Theme.secondaryText)
                        }
                        .padding(40)
                    } else if files.isEmpty {
                        GlassCard { Text("No files above this size.").foregroundColor(Theme.secondaryText) }
                    } else {
                        SectionHeader(title: "Results", trailing: Format.bytes(files.reduce(0) { $0 + $1.bytes }))
                        VStack(spacing: 0) {
                            ForEach(files) { file in
                                row(file)
                                if file.id != files.last?.id {
                                    Divider().background(Color.white.opacity(0.08)).padding(.leading, 60)
                                }
                            }
                        }
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        Text("Photos, messages and other personal databases are never listed. Long-press a file for options.")
                            .font(.caption)
                            .foregroundColor(Theme.secondaryText)
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("Large files")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: threshold) { await load() }
        .confirmationDialog("Delete this file?", isPresented: Binding(get: { pendingDelete != nil },
                                                                      set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { file in
            Button("Delete \(Format.bytes(file.bytes))", role: .destructive) { Task { await delete(file) } }
        } message: { file in
            Text(file.path)
        }
    }

    private func row(_ file: LargeFile) -> some View {
        HStack(spacing: 12) {
            if let owner = file.owner, let icon = AppMeta.icon(for: owner) {
                Image(uiImage: icon).resizable().frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                IconBadge(symbol: symbol(for: file.path), colors: [Theme.amber, Theme.orange], size: 34)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text((file.path as NSString).lastPathComponent)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(file.owner.map { AppMeta.name(for: $0) } ?? (file.path as NSString).deletingLastPathComponent)
                    .font(.caption)
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            Text(Format.bytes(file.bytes))
                .font(.footnote.monospacedDigit().weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .contextMenu {
            Button { UIPasteboard.general.string = file.path } label: { Label("Copy path", systemImage: "doc.on.doc") }
            Button(role: .destructive) { pendingDelete = file } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func symbol(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "mp4", "mov", "m4v", "mkv": return "film.fill"
        case "mp3", "m4a", "aac", "wav", "flac": return "music.note"
        case "zip", "gz", "xz", "tar", "deb", "ipa", "tipa": return "archivebox.fill"
        case "db", "sqlite", "sqlite3": return "cylinder.fill"
        default: return "doc.fill"
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let minBytes = threshold * 1_048_576
            files = try await store.helper.call(LargeFileList.self, ["large", "--min", String(minBytes)]).files
        } catch {
            store.report(error)
        }
    }

    private func delete(_ file: LargeFile) async {
        do {
            let response = try await store.helper.call(CleanResponse.self, ["delete", file.path])
            if response.errors > 0 {
                store.report(HelperError.helper(String(localized: "This file is protected and can't be deleted.")))
            } else {
                withAnimation { files.removeAll { $0.id == file.id } }
                store.show(String(localized: "Freed \(Format.bytes(response.freed))"))
                store.storage = StorageInfo.current()
            }
        } catch {
            store.report(error)
        }
    }
}

// MARK: - Orphans

struct OrphansView: View {
    @EnvironmentObject private var store: AppStore
    @State private var orphans: [Orphan] = []
    @State private var loading = false
    @State private var confirm = false

    var body: some View {
        ZStack(alignment: .bottom) {
            AuroraBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    GlassCard {
                        HStack(spacing: 14) {
                            IconBadge(symbol: "shippingbox.and.arrow.backward.fill", colors: [Theme.orange, Theme.pink], size: 46)
                            Text("Packages that were installed automatically as dependencies and aren't required by anything anymore.")
                                .font(.footnote)
                                .foregroundColor(Theme.secondaryText)
                        }
                    }
                    if loading {
                        ProgressView().frame(maxWidth: .infinity).padding(30)
                    } else if orphans.isEmpty {
                        GlassCard {
                            HStack {
                                Image(systemName: "checkmark.seal.fill").foregroundColor(Theme.mint)
                                Text("No orphaned packages.")
                            }
                        }
                    } else {
                        SectionHeader(title: "Orphaned packages", trailing: "\(orphans.count)")
                        VStack(spacing: 0) {
                            ForEach(orphans) { orphan in
                                HStack {
                                    Text(orphan.name).font(.system(.subheadline, design: .monospaced))
                                    Spacer()
                                    Text(orphan.version).font(.caption).foregroundColor(Theme.secondaryText)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                if orphan.id != orphans.last?.id {
                                    Divider().background(Color.white.opacity(0.08)).padding(.leading, 16)
                                }
                            }
                        }
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
                .padding(18)
                .padding(.bottom, 90)
            }
            if !orphans.isEmpty {
                Button { confirm = true } label: { Label("Remove \(orphans.count) packages", systemImage: "trash") }
                    .buttonStyle(GlowButtonStyle(colors: [Theme.orange, Theme.pink]))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                    .disabled(loading)
            }
        }
        .navigationTitle("Orphaned packages")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog("Remove orphaned packages?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await remove() } }
        } message: {
            Text("This runs apt-get autoremove.")
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do { orphans = try await store.helper.call(OrphanList.self, ["orphans", "list"]).orphans }
        catch { store.report(error) }
    }

    private func remove() async {
        loading = true
        do {
            try await store.helper.perform(["orphans", "remove"])
            store.show(String(localized: "Orphaned packages removed"))
        } catch {
            store.report(error)
        }
        loading = false
        await load()
    }
}

// MARK: - Languages

struct LanguagesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var report: LanguageReport?
    @State private var loading = false
    @State private var confirm = false

    private var keep: [String] {
        var codes = Locale.preferredLanguages.compactMap { $0.split(separator: "-").first.map(String.init) }
        codes.append("en")
        var seen = Set<String>()
        return codes.filter { seen.insert($0).inserted }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AuroraBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(Format.bytes(report?.bytes ?? 0))
                                .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(Theme.aiGradient)
                            Text("in \(Int(report?.count ?? 0)) unused language folders of jailbreak apps and tweaks.")
                                .font(.footnote)
                                .foregroundColor(Theme.secondaryText)
                            Text("Kept: \(keep.joined(separator: ", "))")
                                .font(.caption.monospaced())
                                .foregroundColor(Theme.mint)
                        }
                    }
                    if let languages = report?.languages, !languages.isEmpty {
                        SectionHeader(title: "By language")
                        VStack(spacing: 0) {
                            let sorted = languages.sorted { $0.value > $1.value }
                            ForEach(sorted, id: \.key) { entry in
                                HStack {
                                    Text(Locale.current.localizedString(forLanguageCode: entry.key) ?? entry.key)
                                    Spacer()
                                    Text(Format.bytes(entry.value)).font(.footnote.monospacedDigit())
                                        .foregroundColor(Theme.secondaryText)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                            }
                        }
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    Text("System apps are never touched – removing files from them would break their code signature.")
                        .font(.caption)
                        .foregroundColor(Theme.secondaryText)
                }
                .padding(18)
                .padding(.bottom, 90)
            }
            if (report?.count ?? 0) > 0 {
                Button { confirm = true } label: { Label("Remove unused languages", systemImage: "trash") }
                    .buttonStyle(GlowButtonStyle(colors: [Theme.teal, Theme.mint]))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                    .disabled(loading)
            }
        }
        .navigationTitle("Unused languages")
        .navigationBarTitleDisplayMode(.inline)
        .task { await run(clean: false) }
        .confirmationDialog("Remove unused languages?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await run(clean: true) } }
        } message: {
            Text("Reinstalling a package brings its languages back.")
        }
    }

    private func run(clean: Bool) async {
        loading = true
        defer { loading = false }
        do {
            let result = try await store.helper.call(LanguageReport.self,
                                                     ["languages", clean ? "clean" : "scan", "--keep", keep.joined(separator: ",")])
            if clean {
                store.show(String(localized: "Freed \(Format.bytes(result.freed))"))
                report = try await store.helper.call(LanguageReport.self, ["languages", "scan", "--keep", keep.joined(separator: ",")])
            } else {
                report = result
            }
        } catch {
            store.report(error)
        }
    }
}

// MARK: - Daemons

struct DaemonsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var daemons: [DaemonInfo] = []
    @State private var loading = false

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Only jailbreak daemons are listed. Core jailbreak services are locked to keep your device safe.")
                        .font(.footnote)
                        .foregroundColor(Theme.secondaryText)
                        .padding(.horizontal, 4)
                    if loading && daemons.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(30)
                    } else if daemons.isEmpty {
                        GlassCard { Text("No launch daemons found.").foregroundColor(Theme.secondaryText) }
                    } else {
                        VStack(spacing: 0) {
                            ForEach(daemons) { daemon in
                                row(daemon)
                                if daemon.id != daemons.last?.id {
                                    Divider().background(Color.white.opacity(0.08)).padding(.leading, 16)
                                }
                            }
                        }
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("Launch daemons")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func row(_ daemon: DaemonInfo) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if daemon.locked {
                        Image(systemName: "lock.fill").font(.caption2).foregroundColor(Theme.amber)
                    }
                    Text(daemon.label).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                Text(daemon.program)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { daemon.enabled }, set: { value in Task { await set(daemon, value) } }))
                .labelsHidden()
                .tint(Theme.mint)
                .disabled(daemon.locked)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do { daemons = try await store.helper.call(DaemonList.self, ["daemons", "list"]).daemons }
        catch { store.report(error) }
    }

    private func set(_ daemon: DaemonInfo, _ enabled: Bool) async {
        do {
            try await store.helper.perform(["daemons", "set", enabled ? "on" : "off", daemon.file])
            Haptics.tap()
        } catch {
            store.report(error)
        }
        await load()
    }
}
