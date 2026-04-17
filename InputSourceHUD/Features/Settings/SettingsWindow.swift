import SwiftUI

private enum SettingsScreen: String, CaseIterable, Identifiable {
    case general
    case apps
    case hud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            "General"
        case .apps:
            "Apps"
        case .hud:
            "HUD"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            "Global behavior and startup options"
        case .apps:
            "Per-app switching rules"
        case .hud:
            "Overlay timing and preview"
        }
    }

    var symbolName: String {
        switch self {
        case .general:
            "switch.2"
        case .apps:
            "square.stack.3d.up"
        case .hud:
            "sparkles.rectangle.stack"
        }
    }
}

enum SettingsPalette {
    static let ink = Color(red: 0.11, green: 0.13, blue: 0.17)
    static let steel = Color(red: 0.22, green: 0.26, blue: 0.31)
    static let cloud = Color(red: 0.95, green: 0.96, blue: 0.98)
    static let mist = Color(red: 0.90, green: 0.93, blue: 0.96)
    static let slate = Color(red: 0.55, green: 0.61, blue: 0.69)
    static let accent = Color(red: 0.14, green: 0.55, blue: 0.82)
    static let accentSoft = Color(red: 0.53, green: 0.76, blue: 0.94)
    static let success = Color(red: 0.13, green: 0.60, blue: 0.37)
    static let warning = Color(red: 0.88, green: 0.56, blue: 0.16)
    static let border = Color.white.opacity(0.16)

    static let windowBackground = LinearGradient(
        colors: [
            Color(red: 0.97, green: 0.98, blue: 0.99),
            Color(red: 0.93, green: 0.95, blue: 0.98),
            Color(red: 0.92, green: 0.94, blue: 0.97)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let sidebarBackground = LinearGradient(
        colors: [
            Color(red: 0.12, green: 0.15, blue: 0.19),
            Color(red: 0.17, green: 0.20, blue: 0.26),
            Color(red: 0.12, green: 0.16, blue: 0.22)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardBackground = LinearGradient(
        colors: [
            Color.white.opacity(0.88),
            Color.white.opacity(0.74)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct SettingsWindow: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @EnvironmentObject private var settingsStore: SettingsStore

    @State private var selectedScreen: SettingsScreen = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 1)
                .frame(maxHeight: .infinity)

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(minWidth: 960, minHeight: 620)
        .background {
            ZStack {
                SettingsPalette.windowBackground

                Circle()
                    .fill(SettingsPalette.accentSoft.opacity(0.20))
                    .frame(width: 380, height: 380)
                    .blur(radius: 10)
                    .offset(x: 340, y: -240)

                Circle()
                    .fill(SettingsPalette.warning.opacity(0.10))
                    .frame(width: 260, height: 260)
                    .blur(radius: 8)
                    .offset(x: -180, y: 250)
            }
            .ignoresSafeArea()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsPill(text: "ABC / 한", tint: SettingsPalette.accentSoft, foreground: SettingsPalette.ink)

                VStack(alignment: .leading, spacing: 6) {
                    Text("InputSourceHUD")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("앱 전환 맥락에 맞춰 입력 소스를 고정하고 HUD로 상태를 명확히 보여줍니다.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                SettingsStatTile(title: "Rules", value: "\(settingsStore.settings.apps.count)", tint: SettingsPalette.accentSoft)
                SettingsStatTile(title: "Default", value: currentDefaultInputSourceName, tint: SettingsPalette.warning.opacity(0.85))
                SettingsStatTile(title: "HUD", value: settingsStore.settings.hud.enabled ? "On" : "Off", tint: SettingsPalette.success.opacity(0.85))
                SettingsStatTile(title: "Launch", value: settingsStore.settings.global.launchAtLogin ? "On" : "Off", tint: Color.white.opacity(0.22))
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(SettingsScreen.allCases) { screen in
                    SettingsSidebarButton(
                        title: screen.title,
                        subtitle: screen.subtitle,
                        symbolName: screen.symbolName,
                        isSelected: selectedScreen == screen
                    ) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedScreen = screen
                        }
                    }
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("Current Focus")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(Color.white.opacity(0.50))

                Text(appEnvironment.inputSourceChangeObserver.currentInputSource?.localizedName ?? "Unknown")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 28)
        .frame(width: 288, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background {
            SettingsPalette.sidebarBackground
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch selectedScreen {
            case .general:
                GeneralTab()
            case .apps:
                AppsTab()
            case .hud:
                HUDTab()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var currentDefaultInputSourceName: String {
        let availableSources = appEnvironment.availableInputSources()

        guard
            let defaultID = settingsStore.settings.global.defaultInputSourceId,
            let matchingSource = availableSources.first(where: { $0.id == defaultID })
        else {
            return availableSources.first?.localizedName ?? "Unset"
        }

        return matchingSource.localizedName
    }
}

struct SettingsSidebarButton: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.18) : Color.white.opacity(0.08))
                        .frame(width: 40, height: 40)

                    Image(systemName: symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.60))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.18 : 0.06), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .buttonStyle(.plain)
    }
}

struct SettingsStatTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Color.white.opacity(0.48))

            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

            Capsule()
                .fill(tint)
                .frame(width: 28, height: 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

struct SettingsSectionHeader: View {
    let eyebrow: String
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(SettingsPalette.slate)

            Text(title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(SettingsPalette.ink)

            Text(description)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(SettingsPalette.steel.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SettingsSectionCard<Content: View>: View {
    let title: String
    let description: String?
    let tint: Color
    let content: Content

    init(
        title: String,
        description: String? = nil,
        tint: Color = SettingsPalette.accent,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.description = description
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.18))
                    .frame(width: 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(SettingsPalette.ink)

                    if let description {
                        Text(description)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(SettingsPalette.steel.opacity(0.82))
                    }
                }
            }

            content
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(SettingsPalette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.84), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 10)
    }
}

struct SettingsRow<Accessory: View>: View {
    let title: String
    let description: String
    let accessoryWidth: CGFloat?
    let accessory: Accessory

    init(
        title: String,
        description: String,
        accessoryWidth: CGFloat? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.description = description
        self.accessoryWidth = accessoryWidth
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(SettingsPalette.ink)

                Text(description)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(SettingsPalette.steel.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 24)

            accessory
                .frame(width: accessoryWidth, alignment: .trailing)
        }
    }
}

struct SettingsPill: View {
    let text: String
    let tint: Color
    var foreground: Color = .white

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(0.8)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(tint)
            )
            .foregroundStyle(foreground)
    }
}

struct SettingsInfoCallout: View {
    let title: String
    let message: String
    let symbolName: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(tint.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(SettingsPalette.ink)

                Text(message)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(SettingsPalette.steel.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.66))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

struct SettingsProminentButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minWidth: 120)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.78 : 1.0))
            )
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
    }
}

struct SettingsGhostButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minWidth: 120)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.14 : 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(tint.opacity(0.20), lineWidth: 1)
            )
            .foregroundStyle(SettingsPalette.ink)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
    }
}
