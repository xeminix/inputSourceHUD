import AppKit
import SwiftUI

struct HUDTab: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                SettingsSectionHeader(
                    eyebrow: "OVERLAY",
                    title: "HUD Presentation",
                    description: "입력 소스 전환 결과와 현재 상태를 보여주는 오버레이의 노출 여부와 타이밍을 조절합니다."
                )

                SettingsSectionCard(
                    title: "Visibility",
                    description: "HUD를 켜고 끄거나 표시 시간을 조절합니다.",
                    tint: SettingsPalette.accent
                ) {
                    SettingsRow(
                        title: "Show HUD",
                        description: "전환 성공, 현재 상태 일치, Secure Input 차단 시 HUD를 표시할 수 있습니다."
                    ) {
                        Toggle("", isOn: $settingsStore.settings.hud.enabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    Divider()

                    SettingsRow(
                        title: "Show When Already Matched",
                        description: "앱 규칙과 현재 입력기가 이미 일치해도 READY HUD를 표시합니다."
                    ) {
                        Toggle("", isOn: $settingsStore.settings.hud.showWhenAlreadyMatched)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    Divider()

                    SettingsRow(
                        title: "Show On Manual Changes",
                        description: "사용자가 직접 입력기를 바꿨을 때도 HUD를 표시합니다."
                    ) {
                        Toggle("", isOn: $settingsStore.settings.hud.showOnManualInputSourceChange)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        SettingsRow(
                            title: "Display Duration",
                            description: "오버레이가 화면에 머무는 시간을 0.5초에서 2.0초 사이로 조절합니다."
                        ) {
                            SettingsPill(
                                text: "\(String(format: "%.1f", settingsStore.settings.hud.durationSeconds))s",
                                tint: SettingsPalette.accentSoft.opacity(0.28),
                                foreground: SettingsPalette.ink
                            )
                        }

                        Slider(
                            value: $settingsStore.settings.hud.durationSeconds,
                            in: 0.5 ... 2.0,
                            step: 0.1
                        )
                        .tint(SettingsPalette.accent)

                        HStack {
                            Text("0.5s")
                            Spacer()
                            Text("2.0s")
                        }
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(SettingsPalette.steel.opacity(0.74))
                    }
                }

                SettingsSectionCard(
                    title: "Appearance",
                    description: "HUD의 배경과 글자 투명도를 조절합니다.",
                    tint: SettingsPalette.accent
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingsRow(
                            title: "Background Opacity",
                            description: "배경의 투명도를 조절합니다. 낮을수록 뒤가 비칩니다."
                        ) {
                            SettingsPill(
                                text: "\(Int(settingsStore.settings.hud.backgroundOpacity * 100))%",
                                tint: SettingsPalette.accentSoft.opacity(0.28),
                                foreground: SettingsPalette.ink
                            )
                        }
                        Slider(value: $settingsStore.settings.hud.backgroundOpacity, in: 0.3...1.0, step: 0.05)
                            .tint(SettingsPalette.accent)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        SettingsRow(
                            title: "Text Opacity",
                            description: "글자의 투명도를 조절합니다."
                        ) {
                            SettingsPill(
                                text: "\(Int(settingsStore.settings.hud.textOpacity * 100))%",
                                tint: SettingsPalette.accentSoft.opacity(0.28),
                                foreground: SettingsPalette.ink
                            )
                        }
                        Slider(value: $settingsStore.settings.hud.textOpacity, in: 0.3...1.0, step: 0.05)
                            .tint(SettingsPalette.accent)
                    }

                    Divider()

                    SettingsRow(
                        title: "Background Color",
                        description: "배경 색상을 지정합니다. 끄면 시스템 기본(반투명 블러)을 사용합니다."
                    ) {
                        HStack(spacing: 10) {
                            if settingsStore.settings.hud.backgroundColor != nil {
                                ColorPickerSwatch(selection: backgroundColorBinding)
                            }
                            Toggle("", isOn: backgroundColorEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }

                    Divider()

                    SettingsRow(
                        title: "Main Text",
                        description: "중앙 언어명과 메시지 색상"
                    ) {
                        HStack(spacing: 10) {
                            if settingsStore.settings.hud.mainTextColor != nil {
                                ColorPickerSwatch(selection: mainTextColorBinding)
                            }
                            Toggle("", isOn: mainTextColorEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }

                    Divider()

                    SettingsRow(
                        title: "Identity Text",
                        description: "앱 이름 색상"
                    ) {
                        HStack(spacing: 10) {
                            if settingsStore.settings.hud.identityTextColor != nil {
                                ColorPickerSwatch(selection: identityTextColorBinding)
                            }
                            Toggle("", isOn: identityTextColorEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }

                    Divider()

                    SettingsRow(
                        title: "Badge Text",
                        description: "상태 뱃지(SWITCHED 등) 색상"
                    ) {
                        HStack(spacing: 10) {
                            if settingsStore.settings.hud.badgeTextColor != nil {
                                ColorPickerSwatch(selection: badgeTextColorBinding)
                            }
                            Toggle("", isOn: badgeTextColorEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }

                    Divider()

                    SettingsRow(
                        title: "Detail Text",
                        description: "세부 입력소스명(두벌식 등) 색상"
                    ) {
                        HStack(spacing: 10) {
                            if settingsStore.settings.hud.detailTextColor != nil {
                                ColorPickerSwatch(selection: detailTextColorBinding)
                            }
                            Toggle("", isOn: detailTextColorEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }

                    Divider()

                    HStack {
                        Spacer()
                        Button("Reset Appearance to Default") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                settingsStore.settings.hud.backgroundOpacity = 1.0
                                settingsStore.settings.hud.textOpacity = 1.0
                                settingsStore.settings.hud.backgroundColor = nil
                                settingsStore.settings.hud.mainTextColor = nil
                                settingsStore.settings.hud.identityTextColor = nil
                                settingsStore.settings.hud.badgeTextColor = nil
                                settingsStore.settings.hud.detailTextColor = nil
                            }
                        }
                        .buttonStyle(SettingsProminentButtonStyle(tint: SettingsPalette.slate))
                    }
                }

                SettingsSectionCard(
                    title: "Layout Customization",
                    description: "프리뷰 안의 요소를 드래그해서 미리 지정된 슬롯 사이에서 위치를 바꿀 수 있습니다.",
                    tint: SettingsPalette.warning
                ) {
                    HUDPreviewCanvas(
                        layout: $settingsStore.settings.hud.layout,
                        payload: previewPayload,
                        backgroundOpacity: settingsStore.settings.hud.backgroundOpacity,
                        textOpacity: settingsStore.settings.hud.textOpacity,
                        backgroundColor: settingsStore.settings.hud.backgroundColor?.color,
                        mainTextColor: settingsStore.settings.hud.mainTextColor?.color,
                        identityTextColor: settingsStore.settings.hud.identityTextColor?.color,
                        badgeTextColor: settingsStore.settings.hud.badgeTextColor?.color,
                        detailTextColor: settingsStore.settings.hud.detailTextColor?.color
                    )

                    SettingsInfoCallout(
                        title: "How It Works",
                        message: "프리뷰 안의 요소를 드래그해서 원하는 위치 슬롯에 놓으면 스냅됩니다. 이미 점유된 슬롯에 놓으면 두 요소가 서로 위치를 교환합니다.",
                        symbolName: "hand.draw.fill",
                        tint: SettingsPalette.accent
                    )

                    VStack(spacing: 12) {
                        ForEach(HUDAccessoryKind.allCases) { kind in
                            HUDComponentControlRow(
                                kind: kind,
                                layout: $settingsStore.settings.hud.layout
                            )
                        }
                    }

                    HStack {
                        Button("Preview HUD") {
                            appEnvironment.previewHUD()
                        }
                        .buttonStyle(SettingsProminentButtonStyle(tint: SettingsPalette.accent))

                        Spacer()

                        SettingsPill(
                            text: settingsStore.settings.hud.enabled ? "HUD Enabled" : "HUD Hidden",
                            tint: (settingsStore.settings.hud.enabled ? SettingsPalette.success : SettingsPalette.slate).opacity(0.22),
                            foreground: SettingsPalette.ink
                        )

                        SettingsPill(
                            text: settingsStore.settings.hud.showWhenAlreadyMatched ? "READY HUD On" : "READY HUD Off",
                            tint: (settingsStore.settings.hud.showWhenAlreadyMatched ? SettingsPalette.accent : SettingsPalette.slate).opacity(0.18),
                            foreground: SettingsPalette.ink
                        )

                        SettingsPill(
                            text: settingsStore.settings.hud.showOnManualInputSourceChange ? "Manual HUD On" : "Manual HUD Off",
                            tint: (settingsStore.settings.hud.showOnManualInputSourceChange ? SettingsPalette.accent : SettingsPalette.slate).opacity(0.18),
                            foreground: SettingsPalette.ink
                        )
                    }
                }
            }
            .padding(30)
        }
    }

    private var backgroundColorEnabled: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.hud.backgroundColor != nil },
            set: { enabled in
                settingsStore.settings.hud.backgroundColor = enabled
                    ? CodableColor(red: 0.15, green: 0.15, blue: 0.2)
                    : nil
            }
        )
    }

    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: { settingsStore.settings.hud.backgroundColor?.color ?? Color(red: 0.15, green: 0.15, blue: 0.2) },
            set: { color in
                let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
                settingsStore.settings.hud.backgroundColor = CodableColor(nsColor)
            }
        )
    }

    private var mainTextColorEnabled: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.hud.mainTextColor != nil },
            set: { enabled in
                settingsStore.settings.hud.mainTextColor = enabled
                    ? CodableColor(red: 1.0, green: 1.0, blue: 1.0)
                    : nil
            }
        )
    }

    private var mainTextColorBinding: Binding<Color> {
        Binding(
            get: { settingsStore.settings.hud.mainTextColor?.color ?? .white },
            set: { color in
                let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
                settingsStore.settings.hud.mainTextColor = CodableColor(nsColor)
            }
        )
    }

    private var identityTextColorEnabled: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.hud.identityTextColor != nil },
            set: { enabled in
                settingsStore.settings.hud.identityTextColor = enabled
                    ? CodableColor(red: 0.6, green: 0.6, blue: 0.6)
                    : nil
            }
        )
    }

    private var identityTextColorBinding: Binding<Color> {
        Binding(
            get: { settingsStore.settings.hud.identityTextColor?.color ?? .gray },
            set: { color in
                let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
                settingsStore.settings.hud.identityTextColor = CodableColor(nsColor)
            }
        )
    }

    private var badgeTextColorEnabled: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.hud.badgeTextColor != nil },
            set: { enabled in
                settingsStore.settings.hud.badgeTextColor = enabled
                    ? CodableColor(red: 0.0, green: 0.48, blue: 1.0)
                    : nil
            }
        )
    }

    private var badgeTextColorBinding: Binding<Color> {
        Binding(
            get: { settingsStore.settings.hud.badgeTextColor?.color ?? .blue },
            set: { color in
                let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
                settingsStore.settings.hud.badgeTextColor = CodableColor(nsColor)
            }
        )
    }

    private var detailTextColorEnabled: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.hud.detailTextColor != nil },
            set: { enabled in
                settingsStore.settings.hud.detailTextColor = enabled
                    ? CodableColor(red: 0.6, green: 0.6, blue: 0.6)
                    : nil
            }
        )
    }

    private var detailTextColorBinding: Binding<Color> {
        Binding(
            get: { settingsStore.settings.hud.detailTextColor?.color ?? .gray },
            set: { color in
                let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
                settingsStore.settings.hud.detailTextColor = CodableColor(nsColor)
            }
        )
    }

    private var previewPayload: HUDPayload {
        let currentInputSource = appEnvironment.inputSourceChangeObserver.currentInputSource
        let previewSource = currentInputSource ?? InputSource(
            id: "com.apple.keylayout.ABC",
            localizedName: "ABC",
            shortLabel: "ABC"
        )

        return HUDPayload(
            icon: NSImage(systemSymbolName: "bubble.left.and.bubble.right.fill", accessibilityDescription: nil),
            appName: "Slack",
            languageName: previewSource.hudLanguageName,
            detailName: previewSource.hudDetailName,
            message: "Slack에서 \(previewSource.hudLanguageName)로 변경됨",
            state: .success
        )
    }
}

private struct HUDPreviewCanvas: View {
    @Binding var layout: HUDLayoutSettings
    let payload: HUDPayload
    var backgroundOpacity: Double = 1.0
    var textOpacity: Double = 1.0
    var backgroundColor: Color? = nil
    var mainTextColor: Color? = nil
    var identityTextColor: Color? = nil
    var badgeTextColor: Color? = nil
    var detailTextColor: Color? = nil

    @State private var draggingKind: HUDAccessoryKind?
    @State private var dragTranslation: CGSize = .zero
    @State private var hoveredSlot: HUDAnchorPosition?

    var body: some View {
        ZStack {
            HUDBackgroundCard(accentColor: accentColor, backgroundOpacity: backgroundOpacity, backgroundColor: backgroundColor)

            slotMarkers

            centerContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ForEach(HUDAccessoryKind.allCases) { kind in
                if layout.accessory(for: kind).isVisible {
                    accessoryView(for: kind)
                        .scaleEffect(draggingKind == kind ? 1.03 : 1.0)
                        .shadow(
                            color: Color.black.opacity(draggingKind == kind ? 0.16 : 0.06),
                            radius: draggingKind == kind ? 18 : 8,
                            x: 0,
                            y: draggingKind == kind ? 12 : 4
                        )
                        .position(position(for: kind))
                        .gesture(dragGesture(for: kind))
                        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: layout)
                }
            }
        }
        .frame(width: HUDCanvasMetrics.size.width, height: HUDCanvasMetrics.size.height)
    }

    private var centerContent: some View {
        VStack(spacing: 8) {
            Text(payload.languageName)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(mainTextColor?.opacity(textOpacity) ?? SettingsPalette.ink.opacity(textOpacity))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(payload.message)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(mainTextColor?.opacity(textOpacity * 0.7) ?? SettingsPalette.steel.opacity(0.82 * textOpacity))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 28)
        }
    }

    private var slotMarkers: some View {
        ForEach(HUDAnchorPosition.allCases) { slot in
            let isHovered = hoveredSlot == slot

            Circle()
                .fill(isHovered ? SettingsPalette.accent.opacity(0.22) : SettingsPalette.steel.opacity(0.10))
                .frame(width: isHovered ? 20 : 14, height: isHovered ? 20 : 14)
                .overlay(
                    Circle()
                        .stroke(isHovered ? SettingsPalette.accent.opacity(0.80) : Color.white.opacity(0.72), lineWidth: 1)
                )
                .position(HUDCanvasMetrics.point(for: slot))
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

    private func position(for kind: HUDAccessoryKind) -> CGPoint {
        let basePosition = HUDCanvasMetrics.point(for: layout.accessory(for: kind).position)

        guard draggingKind == kind else {
            return basePosition
        }

        return CGPoint(
            x: basePosition.x + dragTranslation.width,
            y: basePosition.y + dragTranslation.height
        )
    }

    private func dragGesture(for kind: HUDAccessoryKind) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                draggingKind = kind
                dragTranslation = value.translation
                hoveredSlot = nearestSlot(for: kind)
            }
            .onEnded { _ in
                let destination = hoveredSlot ?? layout.accessory(for: kind).position

                withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                    layout.move(kind, to: destination)
                }

                draggingKind = nil
                dragTranslation = .zero
                hoveredSlot = nil
            }
    }

    private func nearestSlot(for kind: HUDAccessoryKind) -> HUDAnchorPosition {
        let draggedPoint = position(for: kind)

        return HUDAnchorPosition.allCases.min { lhs, rhs in
            let lhsPoint = HUDCanvasMetrics.point(for: lhs)
            let rhsPoint = HUDCanvasMetrics.point(for: rhs)
            return lhsPoint.distance(to: draggedPoint) < rhsPoint.distance(to: draggedPoint)
        } ?? layout.accessory(for: kind).position
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

private struct HUDComponentControlRow: View {
    let kind: HUDAccessoryKind
    @Binding var layout: HUDLayoutSettings

    var body: some View {
        SettingsRow(
            title: kind.displayTitle,
            description: kind.descriptionText
        ) {
            HStack(spacing: 10) {
                SettingsPill(
                    text: layout.accessory(for: kind).position.displayTitle,
                    tint: SettingsPalette.accentSoft.opacity(0.22),
                    foreground: SettingsPalette.ink
                )

                Toggle(
                    "",
                    isOn: Binding(
                        get: { layout.accessory(for: kind).isVisible },
                        set: { layout.setVisibility($0, for: kind) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }
        }
    }
}

private extension HUDAccessoryKind {
    var displayTitle: String {
        switch self {
        case .identity:
            "App Identity"
        case .badge:
            "Status Badge"
        case .detail:
            "Detail Label"
        }
    }

    var descriptionText: String {
        switch self {
        case .identity:
            "앱 아이콘과 앱 이름 묶음입니다."
        case .badge:
            "전환 성공 또는 차단 상태를 짧게 보여줍니다."
        case .detail:
            "ABC 또는 두벌식 같은 세부 입력 소스 이름입니다."
        }
    }
}

private extension HUDAnchorPosition {
    var displayTitle: String {
        switch self {
        case .topLeading:
            "Top Left"
        case .topCenter:
            "Top Center"
        case .topTrailing:
            "Top Right"
        case .bottomLeading:
            "Bottom Left"
        case .bottomCenter:
            "Bottom Center"
        case .bottomTrailing:
            "Bottom Right"
        }
    }
}

private struct ColorPickerSwatch: View {
    @Binding var selection: Color

    var body: some View {
        ColorPicker(selection: $selection, supportsOpacity: false) {
            Circle()
                .fill(selection)
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        }
        .labelsHidden()
        .fixedSize()
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        sqrt(pow(x - other.x, 2) + pow(y - other.y, 2))
    }
}
