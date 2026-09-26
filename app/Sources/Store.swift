import SwiftUI

enum AppTab: Hashable { case home, clean, tweaks, tools, settings }

@MainActor
final class AppStore: ObservableObject {
    // Scan & clean
    @Published var results: [String: CategoryResult] = [:]
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var lastClean: CleanResponse?
    @Published var analysis = Analysis()
    @Published var storage = StorageInfo.current()
    @Published var history: [HistoryEntry] = []
    @Published var schedule = ScheduleStatus(enabled: false, hours: 24, categories: [])

    // Navigation & feedback
    @Published var tab: AppTab = .home
    @Published var toolRoute: ToolRoute?
    @Published var showSchedule = false
    @Published var errorMessage: String?
    @Published var toast: String?

    @Published var selection: Set<String> {
        didSet { UserDefaults.standard.set(Array(selection), forKey: "selection") }
    }
    @Published var exclusions: Set<String> {
        didSet { UserDefaults.standard.set(Array(exclusions), forKey: "exclusions") }
    }

    let helper = HelperClient.shared
    var helperAvailable: Bool { helper.helperPath != nil }

    init() {
        let defaults = UserDefaults.standard
        selection = Set(defaults.stringArray(forKey: "selection") ?? Array(CleanCategory.defaultSelection))
        exclusions = Set(defaults.stringArray(forKey: "exclusions") ?? [])
        loadHistory()
    }

    var excludeArgs: [String] {
        exclusions.isEmpty ? [] : ["--exclude", exclusions.sorted().joined(separator: ",")]
    }

    var totalScanned: Int64 { results.values.reduce(0) { $0 + $1.bytes } }

    func bytes(for ids: Set<String>) -> Int64 {
        ids.compactMap { results[$0]?.bytes }.reduce(0, +)
    }

    var allTimeFreed: Int64 { history.reduce(0) { $0 + $1.bytes } }

    // MARK: - Scan

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        do {
            let response = try await helper.call(ScanResponse.self, ["scan"] + excludeArgs + CleanCategory.all.map(\.id))
            var map: [String: CategoryResult] = [:]
            response.categories.forEach { map[$0.id] = $0 }
            withAnimation(.spring()) { results = map }
            storage = StorageInfo.current()
            await refreshSchedule()
            reanalyze()
        } catch {
            report(error)
        }
    }

    func reanalyze() {
        withAnimation(.easeInOut) {
            analysis = SmartAssistant.analyze(results: results, storage: storage, history: history,
                                              exclusions: exclusions, scheduleEnabled: schedule.enabled)
        }
    }

    // MARK: - Clean

    @discardableResult
    func clean(_ ids: Set<String>) async -> CleanResponse? {
        guard !isCleaning, !ids.isEmpty else { return nil }
        isCleaning = true
        defer { isCleaning = false }
        let ordered = CleanCategory.all.map(\.id).filter { ids.contains($0) }
        do {
            let response = try await helper.call(CleanResponse.self, ["clean"] + excludeArgs + ordered)
            lastClean = response
            Haptics.success()
            loadHistory()
            await scan()
            return response
        } catch {
            report(error)
            return nil
        }
    }

    func smartClean() async -> CleanResponse? {
        if results.isEmpty { await scan() }
        let ids = Set(CleanCategory.all.filter { $0.risk == .recommended && (results[$0.id]?.bytes ?? 0) > 0 }.map(\.id))
        return await clean(ids.isEmpty ? CleanCategory.defaultSelection : ids)
    }

    func toggleExclusion(_ bundleID: String) {
        if exclusions.contains(bundleID) { exclusions.remove(bundleID) } else { exclusions.insert(bundleID) }
        reanalyze()
    }

    // MARK: - Schedule

    func refreshSchedule() async {
        if let status = try? await helper.call(ScheduleStatus.self, ["schedule", "status"]) {
            schedule = status
        }
    }

    func setSchedule(hours: Int?, categories: Set<String>) async {
        do {
            if let hours = hours {
                let cats = CleanCategory.all.map(\.id).filter { categories.contains($0) }
                try await helper.perform(["schedule", "set", String(hours)] + excludeArgs + cats)
                show(String(localized: "Automatic cleaning scheduled"))
            } else {
                try await helper.perform(["schedule", "off"])
                show(String(localized: "Automatic cleaning turned off"))
            }
            await refreshSchedule()
            reanalyze()
        } catch {
            report(error)
        }
    }

    // MARK: - Power

    func power(_ action: String) async {
        do { try await helper.perform(["power", action]) } catch { report(error) }
    }

    // MARK: - History

    func loadHistory() {
        let path = helper.jb("/var/mobile/Library/Voidly/history.jsonl")
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        history = text.split(separator: "\n")
            .compactMap { try? decoder.decode(HistoryEntry.self, from: Data($0.utf8)) }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Feedback

    func report(_ error: Error) {
        Haptics.warning()
        errorMessage = error.localizedDescription
    }

    func show(_ message: String) {
        withAnimation(.spring()) { toast = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.easeOut) { if toast == message { toast = nil } }
        }
    }

    // MARK: - Insight actions

    func handle(_ action: Insight.Action) async {
        switch action {
        case .clean(let ids):
            if ids.allSatisfy({ CleanCategory.named($0)?.risk == .recommended }) {
                if let result = await clean(Set(ids)) {
                    show(String(localized: "Freed \(Format.bytes(result.freed))"))
                }
            } else {
                selection = Set(ids)
                tab = .clean
            }
        case .exclude(let bundleID):
            toggleExclusion(bundleID)
            show(String(localized: "\(AppMeta.name(for: bundleID)) excluded"))
            await scan()
        case .openTweaks:
            tab = .tweaks
        case .openSchedule:
            tab = .settings
            showSchedule = true
        case .openLargeFiles:
            tab = .tools
            toolRoute = .largeFiles
        }
    }
}

enum ToolRoute: Hashable { case largeFiles, orphans, languages, daemons }

/// Receives home-screen quick actions before SwiftUI is ready.
final class QuickActionCenter: ObservableObject {
    static let shared = QuickActionCenter()
    @Published var pending: String?
}
