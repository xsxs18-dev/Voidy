import SwiftUI
import UIKit

struct ToolsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var powerAction: PowerAction?

    enum PowerAction: String, Identifiable, CaseIterable {
        case respring, uicache, userspace, ldrestart, reboot
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

        var color: Color {
            switch self {
            case .respring: return Theme.indigo
            case .uicache: return Theme.teal
            case .userspace: return Theme.blue
            case .reboot: return Theme.red
            case .ldrestart: return Theme.orange
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
            List {
                Section {
                    toolLink(.largeFiles, title: "Large files", subtitle: "Find what's eating your storage",
                             icon: "doc.viewfinder.fill", color: Theme.orange) { LargeFilesView() }
                    toolLink(.orphans, title: "Orphaned packages", subtitle: "Dependencies nothing needs anymore",
                             icon: "shippingbox.fill", color: Theme.pink) { OrphansView() }
                    toolLink(.languages, title: "Unused languages", subtitle: "Localizations in jailbreak apps & tweaks",
                             icon: "character.bubble.fill", color: Theme.teal) { LanguagesView() }
                    toolLink(.daemons, title: "Launch daemons", subtitle: "Start or stop jailbreak background services",
                             icon: "gearshape.2.fill", color: Theme.gray) { DaemonsView() }
                } header: {
                    Text("Storage & packages")
                }

                Section {
                    ForEach(PowerAction.allCases) { action in
                        Button {
                            Haptics.tap()
                            powerAction = action
                        } label: {
                            HStack(spacing: 12) {
                                IconBadge(symbol: action.icon, colors: [action.color])
                                Text(LocalizedStringKey(action.title))
                                    .foregroundColor(action == .reboot ? Theme.red : .primary)
                            }
                        }
                    }
                } header: {
                    Text("Power")
                }
            }
            .listStyle(.insetGrouped)
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
                                             color: Color, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(tag: route, selection: $store.toolRoute, destination: destination) {
            HStack(spacing: 12) {
                IconBadge(symbol: icon, colors: [color])
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(title))
                    Text(LocalizedStringKey(subtitle))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
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
        List {
            Section {
                Picker("Minimum size", selection: $threshold) {
                    Text("50 MB").tag(Int64(50))
                    Text("100 MB").tag(Int64(100))
                    Text("250 MB").tag(Int64(250))
                    Text("1 GB").tag(Int64(1024))
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                if loading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Searching your storage…").foregroundColor(.secondary)
                    }
                } else if files.isEmpty {
                    Text("No files above this size.").foregroundColor(.secondary)
                } else {
                    ForEach(files) { file in
                        row(file)
                    }
                }
            } header: {
                if !files.isEmpty && !loading {
                    Text("\(files.count) files · \(Format.bytes(files.reduce(0) { $0 + $1.bytes }))")
                }
            } footer: {
                Text("Photos, messages and other personal databases are never listed. Swipe left to delete.")
            }
        }
        .listStyle(.insetGrouped)
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
            if let owner = file.owner {
                AppIconView(bundleID: owner)
            } else {
                IconBadge(symbol: symbol(for: file.path), colors: [Theme.gray])
            }
            VStack(alignment: .leading, spacing: 2) {
                Text((file.path as NSString).lastPathComponent).lineLimit(1)
                Text(file.owner.map { AppMeta.name(for: $0) } ?? (file.path as NSString).deletingLastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            SizeLabel(bytes: file.bytes)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { pendingDelete = file } label: { Label("Delete", systemImage: "trash") }
        }
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
        List {
            Section {
                if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if orphans.isEmpty {
                    Label("No orphaned packages.", systemImage: "checkmark.circle")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(orphans) { orphan in
                        HStack {
                            Text(orphan.name).font(.system(.body, design: .monospaced))
                            Spacer()
                            Text(orphan.version).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            } footer: {
                Text("Packages that were installed automatically as dependencies and aren't required by anything anymore.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Orphaned packages")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !orphans.isEmpty {
                BottomActionBar(role: .destructive, disabled: loading, action: { confirm = true }) {
                    Label("Remove \(orphans.count) packages", systemImage: "trash")
                }
            }
        }
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
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Format.bytes(report?.bytes ?? 0))
                            .font(.title2.weight(.bold).monospacedDigit())
                        Text("in \(Int(report?.count ?? 0)) unused language folders of jailbreak apps and tweaks.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if loading { ProgressView() }
                }
                .padding(.vertical, 4)
            } footer: {
                Text("Kept: \(keep.joined(separator: ", "))")
            }

            if let languages = report?.languages, !languages.isEmpty {
                Section {
                    ForEach(languages.sorted { $0.value > $1.value }, id: \.key) { entry in
                        HStack {
                            Text(Locale.current.localizedString(forLanguageCode: entry.key) ?? entry.key)
                            Spacer()
                            SizeLabel(bytes: entry.value)
                        }
                    }
                } header: {
                    Text("By language")
                } footer: {
                    Text("System apps are never touched – removing files from them would break their code signature.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Unused languages")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if (report?.count ?? 0) > 0 {
                BottomActionBar(role: .destructive, disabled: loading, action: { confirm = true }) {
                    Label("Remove unused languages", systemImage: "trash")
                }
            }
        }
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
        let keepArg = keep.joined(separator: ",")
        do {
            let result = try await store.helper.call(LanguageReport.self,
                                                     ["languages", clean ? "clean" : "scan", "--keep", keepArg])
            if clean {
                store.show(String(localized: "Freed \(Format.bytes(result.freed))"))
                report = try await store.helper.call(LanguageReport.self, ["languages", "scan", "--keep", keepArg])
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
        List {
            Section {
                if loading && daemons.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if daemons.isEmpty {
                    Text("No launch daemons found.").foregroundColor(.secondary)
                } else {
                    ForEach(daemons) { daemon in
                        Toggle(isOn: Binding(get: { daemon.enabled }, set: { value in Task { await set(daemon, value) } })) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    if daemon.locked {
                                        Image(systemName: "lock.fill").font(.caption2).foregroundColor(.secondary)
                                    }
                                    Text(daemon.label).lineLimit(1)
                                }
                                Text(daemon.program)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .disabled(daemon.locked)
                    }
                }
            } footer: {
                Text("Only jailbreak daemons are listed. Core jailbreak services are locked to keep your device safe.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Launch daemons")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
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
