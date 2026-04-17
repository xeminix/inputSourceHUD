import AppKit
import SwiftUI

enum HUDState {
    case success
    case matched
    case blocked
}

struct HUDPayload {
    let icon: NSImage?
    let appName: String
    let languageName: String
    let detailName: String
    let message: String
    let state: HUDState
}

enum HUDCanvasMetrics {
    static let size = CGSize(width: 332, height: 188)

    static func point(for slot: HUDAnchorPosition, in size: CGSize = size) -> CGPoint {
        let sideX: CGFloat = 78
        let centerX = size.width / 2
        let topY: CGFloat = 34
        let bottomY = size.height - 28

        switch slot {
        case .topLeading:
            return CGPoint(x: sideX, y: topY)
        case .topCenter:
            return CGPoint(x: centerX, y: topY)
        case .topTrailing:
            return CGPoint(x: size.width - sideX, y: topY)
        case .bottomLeading:
            return CGPoint(x: sideX, y: bottomY)
        case .bottomCenter:
            return CGPoint(x: centerX, y: bottomY)
        case .bottomTrailing:
            return CGPoint(x: size.width - sideX, y: bottomY)
        }
    }
}

struct HUDContentView: View {
    let payload: HUDPayload
    let layout: HUDLayoutSettings
    var backgroundOpacity: Double = 1.0
    var textOpacity: Double = 1.0
    var backgroundColor: Color? = nil
    var mainTextColor: Color? = nil
    var identityTextColor: Color? = nil
    var badgeTextColor: Color? = nil
    var detailTextColor: Color? = nil

    var body: some View {
        ZStack {
            HUDBackgroundCard(accentColor: accentColor, backgroundOpacity: backgroundOpacity, backgroundColor: backgroundColor)

            centerContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ForEach(HUDAccessoryKind.allCases) { kind in
                if layout.accessory(for: kind).isVisible {
                    accessoryView(for: kind)
                        .position(HUDCanvasMetrics.point(for: layout.accessory(for: kind).position))
                }
            }
        }
        .frame(width: HUDCanvasMetrics.size.width, height: HUDCanvasMetrics.size.height)
    }

    private var centerContent: some View {
        VStack(spacing: 8) {
            Text(payload.languageName)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(mainTextColor?.opacity(textOpacity) ?? Color.primary.opacity(textOpacity))
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(payload.message)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(mainTextColor?.opacity(textOpacity * 0.7) ?? Color.secondary.opacity(textOpacity))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 28)
        }
    }

    @ViewBuilder
    private func accessoryView(for kind: HUDAccessoryKind) -> some View {
        switch kind {
        case .identity:
            HUDIdentityAccessoryView(payload: payload, accentColor: accentColor, textOpacity: textOpacity, textColor: identityTextColor)
        case .badge:
            HUDStatusBadgeAccessoryView(payload: payload, accentColor: accentColor, textOpacity: textOpacity, textColor: badgeTextColor)
        case .detail:
            HUDDetailAccessoryView(detailName: payload.detailName, accentColor: accentColor, textOpacity: textOpacity, textColor: detailTextColor)
        }
    }

    private var accentColor: Color {
        switch payload.state {
        case .success:
            SettingsPalette.accent
        case .matched:
            SettingsPalette.accent
        case .blocked:
            SettingsPalette.warning
        }
    }
}

struct HUDBackgroundCard: View {
    let accentColor: Color
    var backgroundOpacity: Double = 1.0
    var backgroundColor: Color? = nil

    var body: some View {
        if let backgroundColor {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(backgroundColor.opacity(backgroundOpacity))
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12 * backgroundOpacity),
                            accentColor.opacity(0.06 * backgroundOpacity),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.40 * backgroundOpacity), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(backgroundOpacity)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.24 * backgroundOpacity),
                            accentColor.opacity(0.10 * backgroundOpacity),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.80 * backgroundOpacity), lineWidth: 1)
                )
        }
    }
}

struct HUDIdentityAccessoryView: View {
    let payload: HUDPayload
    let accentColor: Color
    var textOpacity: Double = 1.0
    var textColor: Color? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let icon = payload.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            } else {
                Image(systemName: payload.state == .success ? "app.fill" : "lock.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(textColor?.opacity(textOpacity * 0.7) ?? Color.secondary.opacity(textOpacity))
            }

            Text(payload.appName)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(textColor?.opacity(textOpacity * 0.7) ?? Color.secondary.opacity(textOpacity))
                .lineLimit(1)
        }
    }
}

struct HUDStatusBadgeAccessoryView: View {
    let payload: HUDPayload
    let accentColor: Color
    var textOpacity: Double = 1.0
    var textColor: Color? = nil

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: iconName)
                .font(.system(size: 8, weight: .semibold))

            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(0.6)
        }
        .foregroundStyle(textColor?.opacity(textOpacity) ?? accentColor.opacity(textOpacity))
    }

    private var iconName: String {
        switch payload.state {
        case .success:
            "arrow.triangle.swap"
        case .matched:
            "checkmark.circle.fill"
        case .blocked:
            "lock.fill"
        }
    }

    private var label: String {
        switch payload.state {
        case .success:
            "SWITCHED"
        case .matched:
            "READY"
        case .blocked:
            "BLOCKED"
        }
    }
}

struct HUDDetailAccessoryView: View {
    let detailName: String
    let accentColor: Color
    var textOpacity: Double = 1.0
    var textColor: Color? = nil

    var body: some View {
        Text(detailName)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(textColor?.opacity(textOpacity * 0.7) ?? Color.secondary.opacity(textOpacity))
            .lineLimit(1)
    }
}
