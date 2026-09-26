import SwiftUI
import UIKit

// MARK: - Helper responses

struct ErrorResponse: Decodable { let error: String }
struct OKResponse: Decodable { let ok: Bool?; let message: String? }

struct HelperInfo: Decodable {
    let jbroot: String
    let scheme: String
    let helper: String
    let version: String
}

struct ScanResponse: Decodable { let categories: [CategoryResult] }

struct CategoryResult: Decodable, Identifiable {
    let id: String
    let bytes: Int64
    let files: Int64
    let items: [ScanItem]
}

struct ScanItem: Decodable, Identifiable, Hashable {
    var id: String { name + path }
    let name: String
    let path: String
    let bytes: Int64
    let files: Int64
}

struct CleanResponse: Decodable {
    let freed: Int64
    let files: Int64
    let errors: Int64
    let categories: [String: Int64]
}

struct TweakList: Decodable { let tweaks: [TweakInfo] }

struct TweakInfo: Decodable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    var enabled: Bool
    let filters: [String]
    let executables: [String]
    let bytes: Int64
    let modified: Double
    let package: String?
}

struct DaemonList: Decodable { let daemons: [DaemonInfo] }

struct DaemonInfo: Decodable, Identifiable, Hashable {
    var id: String { file }
    let file: String
    let label: String
    let program: String
    var enabled: Bool
    let locked: Bool
}

struct LargeFileList: Decodable { let files: [LargeFile] }

struct LargeFile: Decodable, Identifiable, Hashable {
    var id: String { path }
    let path: String
    let bytes: Int64
    let modified: Double
    let owner: String?
}

struct OrphanList: Decodable { let orphans: [Orphan] }

struct Orphan: Decodable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let version: String
}

struct LanguageReport: Decodable {
    let bytes: Int64
    let count: Int64
    let freed: Int64
    let languages: [String: Int64]
}

struct ScheduleStatus: Decodable {
    let enabled: Bool
    let hours: Int
    let categories: [String]
}

struct HistoryEntry: Decodable, Identifiable, Hashable {
    var id: Double { date }
    let date: Double
    let bytes: Int64
    let files: Int64
    let categories: [String]
    let auto: Bool
}

// MARK: - Clean categories

enum Risk: String, CaseIterable {
    case recommended, advanced, privacy

    var title: String {
        switch self {
        case .recommended: return "Recommended"
        case .advanced: return "Advanced"
        case .privacy: return "Privacy"
        }
    }

    var tint: Color {
        switch self {
        case .recommended: return Theme.mint
        case .advanced: return Theme.amber
        case .privacy: return Theme.pink
        }
    }
}

struct CleanCategory: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let risk: Risk
    let colors: [Color]

    static let all: [CleanCategory] = [
        .init(id: "app_caches", title: "App Caches", subtitle: "Cache files your apps rebuild on demand",
              icon: "square.stack.3d.up.fill", risk: .recommended, colors: [Theme.violet, Theme.indigo]),
        .init(id: "safari_cache", title: "Safari Cache", subtitle: "Cached pages & WebKit data",
              icon: "safari.fill", risk: .recommended, colors: [Theme.cyan, Theme.blue]),
        .init(id: "temp", title: "Temporary Files", subtitle: "Leftovers in tmp folders older than a day",
              icon: "clock.arrow.circlepath", risk: .recommended, colors: [Theme.teal, Theme.mint]),
        .init(id: "crash_logs", title: "Crash Reports", subtitle: "Crash & diagnostic reports",
              icon: "exclamationmark.triangle.fill", risk: .recommended, colors: [Theme.amber, Theme.orange]),
        .init(id: "logs", title: "Log Files", subtitle: "System and jailbreak log files",
              icon: "doc.text.fill", risk: .recommended, colors: [Theme.blue, Theme.indigo]),
        .init(id: "pkg_cache", title: "Package Cache", subtitle: "Downloaded .debs & package manager caches",
              icon: "shippingbox.fill", risk: .recommended, colors: [Theme.orange, Theme.pink]),
        .init(id: "shared_caches", title: "Tweak & Shared Caches", subtitle: "Caches of tweaks and jailbreak apps",
              icon: "puzzlepiece.extension.fill", risk: .recommended, colors: [Theme.pink, Theme.violet]),
        .init(id: "apt_lists", title: "Repository Lists", subtitle: "Re-downloaded on the next refresh",
              icon: "list.bullet.rectangle.fill", risk: .advanced, colors: [Theme.amber, Theme.teal]),
        .init(id: "safari_history", title: "Browsing History", subtitle: "Safari history & recently closed tabs",
              icon: "clock.fill", risk: .privacy, colors: [Theme.pink, Theme.orange]),
        .init(id: "web_data", title: "Cookies & Website Data", subtitle: "Signs you out of websites",
              icon: "globe", risk: .privacy, colors: [Theme.indigo, Theme.pink]),
        .init(id: "keyboard", title: "Keyboard Learning", subtitle: "Resets predictive text learning",
              icon: "keyboard", risk: .privacy, colors: [Theme.teal, Theme.violet]),
    ]

    static let defaultSelection: Set<String> = Set(all.filter { $0.risk == .recommended }.map(\.id))

    static func named(_ id: String) -> CleanCategory? { all.first { $0.id == id } }
}

// MARK: - Storage

struct StorageInfo {
    let total: Int64
    let free: Int64
    var used: Int64 { max(0, total - free) }
    var freeRatio: Double { total > 0 ? Double(free) / Double(total) : 1 }

    static func current() -> StorageInfo {
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/private/var")
        let total = (attrs?[.systemSize] as? NSNumber)?.int64Value ?? 0
        let free = (attrs?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        return StorageInfo(total: total, free: free)
    }
}

// MARK: - Formatting

enum Format {
    static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: value)
    }

    static func date(_ timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - App metadata (names & icons via private LaunchServices / UIKit API)

enum AppMeta {
    private static var names: [String: String] = [:]
    private static var icons: [String: UIImage] = [:]

    static func name(for bundleID: String) -> String {
        if let cached = names[bundleID] { return cached }
        var result = bundleID
        if bundleID == "com.apple.springboard" {
            result = "SpringBoard"
        } else if let proxy = applicationProxy(for: bundleID),
                  let localized = proxy.value(forKey: "localizedName") as? String, !localized.isEmpty {
            result = localized
        }
        names[bundleID] = result
        return result
    }

    private static func applicationProxy(for bundleID: String) -> NSObject? {
        typealias ProxyFn = @convention(c) (AnyClass, Selector, NSString) -> NSObject?
        let selector = NSSelectorFromString("applicationProxyForIdentifier:")
        guard let cls = NSClassFromString("LSApplicationProxy"),
              let method = class_getClassMethod(cls, selector) else { return nil }
        let fn = unsafeBitCast(method_getImplementation(method), to: ProxyFn.self)
        return fn(cls, selector, bundleID as NSString)
    }

    static func icon(for bundleID: String) -> UIImage? {
        if let cached = icons[bundleID] { return cached }
        typealias IconFn = @convention(c) (AnyClass, Selector, NSString, Int32, CGFloat) -> UIImage?
        let selector = NSSelectorFromString("_applicationIconImageForBundleIdentifier:format:scale:")
        guard let method = class_getClassMethod(UIImage.self, selector) else { return nil }
        let fn = unsafeBitCast(method_getImplementation(method), to: IconFn.self)
        let image = fn(UIImage.self, selector, bundleID as NSString, 2, UIScreen.main.scale)
        if let image = image { icons[bundleID] = image }
        return image
    }
}
