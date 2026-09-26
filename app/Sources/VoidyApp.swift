import SwiftUI
import UIKit
import Combine

@main
struct VoidyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem {
            QuickActionCenter.shared.pending = item.type
        }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        QuickActionCenter.shared.pending = shortcutItem.type
        completionHandler(true)
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var quickActions = QuickActionCenter.shared

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $store.tab) {
                HomeView()
                    .tabItem { Label("Home", systemImage: "sparkles") }
                    .tag(AppTab.home)
                CleanView()
                    .tabItem { Label("Clean", systemImage: "wand.and.stars") }
                    .tag(AppTab.clean)
                TweaksView()
                    .tabItem { Label("Tweaks", systemImage: "puzzlepiece.extension.fill") }
                    .tag(AppTab.tweaks)
                ToolsView()
                    .tabItem { Label("Tools", systemImage: "square.grid.2x2.fill") }
                    .tag(AppTab.tools)
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                    .tag(AppTab.settings)
            }

            if let toast = store.toast {
                ToastView(text: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
                    .zIndex(1)
            }
        }
        .alert(isPresented: Binding(get: { store.errorMessage != nil },
                                    set: { if !$0 { store.errorMessage = nil } })) {
            Alert(title: Text("Something went wrong"),
                  message: Text(store.errorMessage ?? ""),
                  dismissButton: .default(Text("OK")))
        }
        .task { await store.scan() }
        .onReceive(quickActions.$pending.compactMap { $0 }) { type in
            quickActions.pending = nil
            Task { await runQuickAction(type) }
        }
    }

    private func runQuickAction(_ type: String) async {
        if type.hasSuffix(".respring") {
            await store.power("respring")
        } else if type.hasSuffix(".smartclean") {
            store.tab = .home
            if let result = await store.smartClean() {
                store.show(String(localized: "Freed \(Format.bytes(result.freed))"))
            }
        }
    }
}

struct ToastView: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.mint)
            Text(text).font(.system(.subheadline, design: .rounded).weight(.semibold))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
    }
}
