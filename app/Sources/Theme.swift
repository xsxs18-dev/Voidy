import SwiftUI
import UIKit

enum Theme {
    static let violet = Color(red: 0.55, green: 0.38, blue: 1.00)
    static let indigo = Color(red: 0.36, green: 0.40, blue: 1.00)
    static let blue   = Color(red: 0.25, green: 0.56, blue: 1.00)
    static let cyan   = Color(red: 0.22, green: 0.84, blue: 1.00)
    static let teal   = Color(red: 0.20, green: 0.83, blue: 0.78)
    static let mint   = Color(red: 0.35, green: 0.92, blue: 0.62)
    static let amber  = Color(red: 1.00, green: 0.76, blue: 0.28)
    static let orange = Color(red: 1.00, green: 0.55, blue: 0.30)
    static let pink   = Color(red: 1.00, green: 0.38, blue: 0.72)

    static let background = Color(red: 0.035, green: 0.035, blue: 0.07)
    static let secondaryText = Color.white.opacity(0.6)

    static let aiGradient = LinearGradient(colors: [violet, blue, cyan],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
    static let aiAngular = AngularGradient(colors: [violet, cyan, mint, pink, violet], center: .center)

    static func configureUIKitAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        nav.titleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        tab.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        tab.backgroundColor = UIColor(white: 0.03, alpha: 0.4)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        UITableView.appearance().backgroundColor = .clear
    }
}

// MARK: - Background

/// Deep dark canvas with slowly drifting, blurred colour blobs.
struct AuroraBackground: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            Theme.background
            Circle()
                .fill(Theme.violet.opacity(0.35))
                .frame(width: 380, height: 380)
                .blur(radius: 120)
                .offset(x: animate ? -120 : -60, y: animate ? -300 : -220)
            Circle()
                .fill(Theme.cyan.opacity(0.22))
                .frame(width: 320, height: 320)
                .blur(radius: 120)
                .offset(x: animate ? 150 : 90, y: animate ? -80 : -160)
            Circle()
                .fill(Theme.pink.opacity(0.15))
                .frame(width: 300, height: 300)
                .blur(radius: 130)
                .offset(x: animate ? -40 : 60, y: animate ? 360 : 280)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 12).repeatForever(autoreverses: true)) { animate = true }
        }
    }
}

// MARK: - Cards

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(LocalizedStringKey(title))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .textCase(.uppercase)
                .foregroundColor(Theme.secondaryText)
            Spacer()
            if let trailing = trailing {
                Text(trailing).font(.footnote.monospacedDigit()).foregroundColor(Theme.secondaryText)
            }
        }
        .padding(.horizontal, 4)
    }
}

struct IconBadge: View {
    let symbol: String
    var colors: [Color] = [Theme.violet, Theme.cyan]
    var size: CGFloat = 38

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundColor(.white)
            )
            .shadow(color: (colors.first ?? .clear).opacity(0.45), radius: 8, y: 3)
    }
}

// MARK: - Buttons

struct GlowButtonStyle: ButtonStyle {
    var colors: [Color] = [Theme.violet, Theme.blue, Theme.cyan]

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded))
            .foregroundColor(.white)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
            )
            .shadow(color: (colors.first ?? .clear).opacity(configuration.isPressed ? 0.2 : 0.55), radius: 18, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct PillButtonStyle: ButtonStyle {
    var tint: Color = Theme.violet

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.45 : 0.3)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.6), lineWidth: 1))
    }
}

// MARK: - AI orb

/// The animated "intelligence" orb shown on the dashboard.
struct AIOrb: View {
    var active: Bool
    var size: CGFloat = 200

    @State private var rotation = 0.0
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.aiAngular)
                .frame(width: size, height: size)
                .blur(radius: size * 0.18)
                .opacity(active ? 0.9 : 0.55)
                .scaleEffect(pulse ? 1.08 : 0.94)
                .rotationEffect(.degrees(rotation))

            Circle()
                .fill(RadialGradient(colors: [Color.white.opacity(0.18), Theme.background.opacity(0.9)],
                                     center: .topLeading, startRadius: 4, endRadius: size * 0.7))
                .frame(width: size * 0.78, height: size * 0.78)
                .overlay(
                    Circle().strokeBorder(Theme.aiAngular, lineWidth: 2)
                        .rotationEffect(.degrees(-rotation * 1.5))
                        .opacity(0.8)
                )
        }
        .onAppear {
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) { rotation = 360 }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

// MARK: - Typewriter

/// Reveals text character by character – used for the assistant summary.
struct TypewriterText: View {
    let text: String
    @State private var visible = 0

    var body: some View {
        Text(String(text.prefix(visible)))
            .task(id: text) {
                visible = 0
                for index in 0...text.count {
                    visible = index
                    try? await Task.sleep(nanoseconds: 12_000_000)
                    if Task.isCancelled { return }
                }
            }
    }
}

// MARK: - Ring chart

struct RingSegment: Identifiable {
    let id = UUID()
    let value: Double
    let color: Color
}

struct RingChart: View {
    let segments: [RingSegment]
    var lineWidth: CGFloat = 16

    var body: some View {
        let total = max(segments.reduce(0) { $0 + $1.value }, 1)
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                let start = segments.prefix(index).reduce(0) { $0 + $1.value } / total
                let end = start + segment.value / total
                Circle()
                    .trim(from: CGFloat(start), to: CGFloat(max(start, end - 0.004)))
                    .stroke(segment.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

struct ScoreRing: View {
    let score: Int

    var color: Color {
        switch score {
        case 80...: return Theme.mint
        case 55..<80: return Theme.amber
        default: return Theme.pink
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: 6)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(AngularGradient(colors: [color.opacity(0.6), color], center: .center),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.8), value: score)
            Text("\(score)")
                .font(.system(.headline, design: .rounded).monospacedDigit())
                .foregroundColor(.white)
        }
    }
}

// MARK: - Haptics

enum Haptics {
    static var enabled: Bool { UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true }

    static func success() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func tap() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
