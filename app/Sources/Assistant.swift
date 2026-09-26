import SwiftUI

/// On-device heuristics that turn a scan into readable advice.
/// Simple rules that run entirely on the device.
struct Insight: Identifiable {
    enum Action: Equatable {
        case clean([String])
        case exclude(String)
        case openTweaks
        case openSchedule
        case openLargeFiles
    }

    let id = UUID()
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    var action: Action? = nil
    var actionTitle: String? = nil
    var priority: Int = 0
}

struct Analysis {
    var insights: [Insight] = []
    var summary: String = ""
    var score: Int = 100
    var safeBytes: Int64 = 0
}

enum SmartAssistant {
    static let gigabyte: Int64 = 1_073_741_824
    static let megabyte: Int64 = 1_048_576

    static func analyze(results: [String: CategoryResult],
                        storage: StorageInfo,
                        history: [HistoryEntry],
                        exclusions: Set<String>,
                        scheduleEnabled: Bool) -> Analysis {
        var analysis = Analysis()
        guard !results.isEmpty else {
            analysis.summary = String(localized: "Run a Smart Scan and I'll tell you what's worth cleaning.")
            return analysis
        }

        let safeIDs = CleanCategory.all.filter { $0.risk == .recommended }.map(\.id)
        let safe = safeIDs.compactMap { results[$0] }.filter { $0.bytes > 0 }
        let safeBytes = safe.reduce(Int64(0)) { $0 + $1.bytes }
        analysis.safeBytes = safeBytes
        var insights: [Insight] = []
        var sentences: [String] = []

        // 1. Headline: how much can go safely.
        if safeBytes > 0 {
            let biggest = safe.max { $0.bytes < $1.bytes }
            let biggestName = biggest.flatMap { CleanCategory.named($0.id)?.title }.map { NSLocalizedString($0, comment: "") } ?? ""
            sentences.append(String(localized: "I found \(Format.bytes(safeBytes)) you can remove without any risk."))
            if !biggestName.isEmpty {
                sentences.append(String(localized: "Most of it comes from \(biggestName)."))
            }
            insights.append(Insight(icon: "sparkles", tint: Theme.cyan,
                                    title: String(localized: "\(Format.bytes(safeBytes)) ready to clean"),
                                    detail: String(localized: "Only caches, logs and leftovers – nothing personal is touched."),
                                    action: .clean(safe.map(\.id)),
                                    actionTitle: String(localized: "Clean now"),
                                    priority: 100))
        } else {
            sentences.append(String(localized: "Your device is already spotless."))
        }

        // 2. App caches: heavy hitters and possible offline content.
        if let caches = results["app_caches"], caches.bytes > 0 {
            let top = caches.items.prefix(3)
            let topBytes = top.reduce(Int64(0)) { $0 + $1.bytes }
            if caches.items.count > 3, Double(topBytes) / Double(caches.bytes) > 0.6 {
                let names = top.map { AppMeta.name(for: $0.name) }.joined(separator: ", ")
                let share = Int(Double(topBytes) / Double(caches.bytes) * 100)
                sentences.append(String(localized: "\(names) are responsible for \(share)% of all app caches."))
            }
            if let heavy = caches.items.first, heavy.bytes > gigabyte, !exclusions.contains(heavy.name) {
                let name = AppMeta.name(for: heavy.name)
                insights.append(Insight(icon: "externaldrive.fill.badge.exclamationmark", tint: Theme.amber,
                                        title: String(localized: "\(name) caches \(Format.bytes(heavy.bytes))"),
                                        detail: String(localized: "If it keeps offline music, videos or maps in its cache, exclude it so nothing needs to be re-downloaded."),
                                        action: .exclude(heavy.name),
                                        actionTitle: String(localized: "Exclude"),
                                        priority: 70))
            }
        }

        // 3. Crash reports: detect crash loops.
        if let crashes = results["crash_logs"], crashes.files > 0 {
            let loops = crashes.items.filter { $0.files >= 5 }.prefix(2)
            if let worst = loops.first {
                sentences.append(String(localized: "\(worst.name) crashed \(Int(worst.files)) times – a tweak might be misbehaving."))
                insights.append(Insight(icon: "waveform.path.ecg", tint: Theme.pink,
                                        title: String(localized: "\(worst.name) keeps crashing"),
                                        detail: String(localized: "\(Int(worst.files)) crash reports found. Recently installed tweaks are the usual suspect."),
                                        action: .openTweaks,
                                        actionTitle: String(localized: "Review tweaks"),
                                        priority: 80))
            }
        }

        // 4. Low storage.
        if storage.total > 0, storage.freeRatio < 0.1 {
            insights.append(Insight(icon: "exclamationmark.octagon.fill", tint: Theme.pink,
                                    title: String(localized: "Storage almost full"),
                                    detail: String(localized: "Only \(Format.bytes(storage.free)) left. Large files are often the fastest win."),
                                    action: .openLargeFiles,
                                    actionTitle: String(localized: "Find large files"),
                                    priority: 90))
        }

        // 5. Package cache.
        if let packages = results["pkg_cache"], packages.bytes > 150 * megabyte {
            insights.append(Insight(icon: "shippingbox.fill", tint: Theme.orange,
                                    title: String(localized: "\(Format.bytes(packages.bytes)) of old .deb files"),
                                    detail: String(localized: "Installed packages don't need their downloaded archives anymore."),
                                    action: .clean(["pkg_cache"]),
                                    actionTitle: String(localized: "Clean"),
                                    priority: 50))
        }

        // 6. Privacy data.
        let privacy = ["safari_history", "web_data", "keyboard"].compactMap { results[$0] }.filter { $0.files > 0 }
        if !privacy.isEmpty {
            insights.append(Insight(icon: "hand.raised.fill", tint: Theme.violet,
                                    title: String(localized: "Privacy traces found"),
                                    detail: String(localized: "History, cookies and keyboard learning can be wiped – they are never cleaned automatically."),
                                    action: .clean(privacy.map(\.id)),
                                    actionTitle: String(localized: "Review"),
                                    priority: 20))
        }

        // 7. Habit: remind about automatic cleaning.
        let lastClean = history.map(\.date).max() ?? 0
        if !scheduleEnabled, Date().timeIntervalSince1970 - lastClean > 14 * 86_400 {
            insights.append(Insight(icon: "calendar.badge.clock", tint: Theme.teal,
                                    title: String(localized: "Let Purify clean on its own"),
                                    detail: String(localized: "Schedule a quiet background clean so caches never pile up again."),
                                    action: .openSchedule,
                                    actionTitle: String(localized: "Set up"),
                                    priority: 10))
        }

        // Health score.
        var score = 100
        if storage.freeRatio < 0.1 { score -= 25 } else if storage.freeRatio < 0.2 { score -= 10 }
        score -= min(30, Int(Double(safeBytes) / Double(gigabyte) * 10))
        if let crashes = results["crash_logs"] {
            if crashes.files > 100 { score -= 20 } else if crashes.files > 20 { score -= 10 }
        }

        analysis.score = max(0, min(100, score))
        analysis.insights = insights.sorted { $0.priority > $1.priority }
        analysis.summary = sentences.joined(separator: " ")
        return analysis
    }
}
