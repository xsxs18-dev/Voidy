import SwiftUI
import UIKit

/// Minimal, native look: system colours, grouped lists, Settings-style icons.
enum Theme {
    static let accent = Color(red: 0.36, green: 0.40, blue: 0.96)

    static let violet = Color(.systemPurple)
    static let indigo = Color(.systemIndigo)
    static let blue   = Color(.systemBlue)
    static let cyan   = Color(.systemCyan)
    static let teal   = Color(.systemTeal)
    static let mint   = Color(.systemGreen)
    static let amber  = Color(.systemYellow)
    static let orange = Color(.systemOrange)
    static let pink   = Color(.systemPink)
    static let red    = Color(.systemRed)
    static let gray   = Color(.systemGray)
}

// MARK: - Icons

/// Rounded square icon like the ones in the Settings app.
struct IconBadge: View {
    let symbol: String
    var colors: [Color] = [Theme.accent]
    var size: CGFloat = 29

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(colors.first ?? Theme.accent)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundColor(.white)
            )
    }
}

/// App icon for a bundle id, falling back to a neutral badge.
struct AppIconView: View {
    let bundleID: String
    var size: CGFloat = 29

    var body: some View {
        if let icon = AppMeta.icon(for: bundleID) {
            Image(uiImage: icon)
                .resizable()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        } else {
            IconBadge(symbol: "app.fill", colors: [Theme.gray], size: size)
        }
    }
}

// MARK: - Storage bar

struct BarSegment: Identifiable {
    let id = UUID()
    let value: Double
    let color: Color
}

/// Horizontal segmented bar showing how storage is split.
struct StorageBar: View {
    let segments: [BarSegment]
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let total = max(segments.reduce(0) { $0 + $1.value }, 1)
            HStack(spacing: 2) {
                ForEach(segments) { segment in
                    if segment.value > 0 {
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: max(2, (geo.size.width - CGFloat(segments.count * 2)) * CGFloat(segment.value / total)))
                    }
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
        }
        .frame(height: height)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}

struct LegendDot: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(LocalizedStringKey(title))
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }
}

struct ScoreRing: View {
    let score: Int

    var color: Color {
        switch score {
        case 80...: return Theme.mint
        case 55..<80: return Theme.orange
        default: return Theme.red
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color(.tertiarySystemFill), lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: score)
            Text("\(score)")
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
        }
    }
}

/// Size label used on the trailing edge of list rows.
struct SizeLabel: View {
    let bytes: Int64

    var body: some View {
        Text(Format.bytes(bytes))
            .font(.subheadline.monospacedDigit())
            .foregroundColor(.secondary)
    }
}

/// Full-width primary action pinned to the bottom of a screen.
struct BottomActionBar<Label: View>: View {
    var role: ButtonRole? = nil
    var disabled = false
    let action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            Button(role: role, action: action) {
                label.frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(disabled)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.bar)
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
