import SwiftUI

struct AppsTab: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @EnvironmentObject private var settingsStore: SettingsStore

    private let appGridColumns = [
        GridItem(.adaptive(minimum: 190), spacing: 12)
    ]

    private var availableInputSources: [InputSource] {
        appEnvironment.availableInputSources()
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                SettingsSectionHeader(
                    eyebrow: "PER-APP",
                    title: "Application Rules",
                    description: "최근 사용 앱, 실행 중인 앱, 직접 선택한 앱을 바로 규칙으로 추가하고 `force`, `use global default`, `ignore` 정책을 관리합니다."
                )

                SettingsSectionCard(
                    title: "Add Rules",
                    description: "새 규칙은 기본적으로 전역 기본 입력 소스로 즉시 전환되도록 추가됩니다.",
                    tint: SettingsPalette.accent
                ) {
                    HStack(spacing: 12) {
                        Button("Add Frontmost App") {
                            appEnvironment.addRuleForFrontmostApplication()
                        }
                        .buttonStyle(SettingsProminentButtonStyle(tint: SettingsPalette.accent))

                        Button("Choose App…") {
                            appEnvironment.addRuleFromApplicationPicker()
                        }
                        .buttonStyle(SettingsGhostButtonStyle(tint: SettingsPalette.steel))

                        Spacer()

                        SettingsPill(
                            text: "\(settingsStore.settings.apps.count) rule(s)",
                            tint: SettingsPalette.accentSoft.opacity(0.28),
                            foreground: SettingsPalette.ink
                        )
                    }

                    SettingsInfoCallout(
                        title: "Application Picker",
                        message: "직접 선택은 기본적으로 Applications 폴더에서 시작하고, 추가된 규칙은 현재 전역 기본 입력 소스로 force됩니다.",
                        symbolName: "folder.fill",
                        tint: SettingsPalette.warning
                    )

                    if let defaultInputSource = appEnvironment.defaultRuleInputSource() {
                        SettingsInfoCallout(
                            title: "Default Rule Target",
                            message: "지금 새 규칙을 추가하면 기본적으로 `\(defaultInputSource.hudDetailName)`로 전환되도록 설정됩니다. 아래 Recent Apps / Running Apps 카드에서는 입력기를 바로 지정할 수 있습니다.",
                            symbolName: "character.cursor.ibeam",
                            tint: SettingsPalette.accent
                        )
                    }
                }

                SettingsSectionCard(
                    title: "Recent Apps",
                    description: "최근 전면으로 전환한 앱들입니다.",
                    tint: SettingsPalette.warning
                ) {
                    if appEnvironment.recentApplications.isEmpty {
                        SettingsInfoCallout(
                            title: "No Recent Apps Yet",
                            message: "앱을 몇 번 전환하면 최근 사용 앱 목록이 여기에 쌓입니다.",
                            symbolName: "clock.arrow.circlepath",
                            tint: SettingsPalette.warning
                        )
                    } else {
                        LazyVGrid(columns: appGridColumns, spacing: 12) {
                            ForEach(appEnvironment.recentApplications) { item in
                                AppSelectionCard(
                                    item: item,
                                    availableInputSources: availableInputSources,
                                    currentRule: appEnvironment.rule(for: item.bundleID)
                                ) {
                                    selectedInputSource in
                                    appEnvironment.assignRule(for: item, inputSourceID: selectedInputSource.id)
                                }
                            }
                        }
                    }
                }

                SettingsSectionCard(
                    title: "Running Apps",
                    description: "현재 실행 중인 앱을 바로 규칙으로 추가할 수 있습니다.",
                    tint: SettingsPalette.accentSoft
                ) {
                    if appEnvironment.runningApplications.isEmpty {
                        SettingsInfoCallout(
                            title: "No Running Apps",
                            message: "표시 가능한 일반 앱이 실행 중이지 않으면 이 목록은 비어 있습니다.",
                            symbolName: "app.dashed",
                            tint: SettingsPalette.steel
                        )
                    } else {
                        LazyVGrid(columns: appGridColumns, spacing: 12) {
                            ForEach(appEnvironment.runningApplications) { item in
                                AppSelectionCard(
                                    item: item,
                                    availableInputSources: availableInputSources,
                                    currentRule: appEnvironment.rule(for: item.bundleID)
                                ) {
                                    selectedInputSource in
                                    appEnvironment.assignRule(for: item, inputSourceID: selectedInputSource.id)
                                }
                            }
                        }
                    }
                }

                if settingsStore.settings.apps.isEmpty {
                    SettingsSectionCard(
                        title: "No Rules Yet",
                        description: "위 목록에서 앱을 하나 고르면 바로 규칙 편집을 시작할 수 있습니다.",
                        tint: SettingsPalette.accentSoft
                    ) {
                        SettingsInfoCallout(
                            title: "Recommended Start",
                            message: "Xcode와 Terminal은 ABC, Slack과 메신저는 두벌식으로 두면 가장 큰 체감이 납니다.",
                            symbolName: "sparkles",
                            tint: SettingsPalette.accent
                        )
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach($settingsStore.settings.apps) { $rule in
                            AppRuleRow(
                                rule: $rule,
                                availableInputSources: availableInputSources
                            ) {
                                removeRule(bundleID: rule.bundleId)
                            }
                        }
                    }
                }
            }
            .padding(30)
        }
        .onAppear {
            appEnvironment.refreshApplicationCatalogs()
        }
    }

    private func removeRule(bundleID: String) {
        settingsStore.settings.apps.removeAll { $0.bundleId == bundleID }
    }
}

private struct AppSelectionCard: View {
    let item: AppSelectionItem
    let availableInputSources: [InputSource]
    let currentRule: AppRule?
    let onSelectInputSource: (InputSource) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                appIcon

                Spacer(minLength: 0)

                if let currentRule {
                    SettingsPill(
                        text: currentRuleBadgeTitle(for: currentRule),
                        tint: currentRuleBadgeTint(for: currentRule),
                        foreground: currentRuleBadgeForeground(for: currentRule)
                    )
                } else if item.isFrontmost {
                    SettingsPill(
                        text: "ACTIVE",
                        tint: SettingsPalette.success.opacity(0.88)
                    )
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(SettingsPalette.ink)
                    .lineLimit(1)

                Text(item.subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(SettingsPalette.steel.opacity(0.72))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                Text("Quick Assign")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(SettingsPalette.steel.opacity(0.76))

                HStack(spacing: 8) {
                    ForEach(availableInputSources) { inputSource in
                        Button(inputSource.hudDetailName) {
                            onSelectInputSource(inputSource)
                        }
                        .buttonStyle(
                            AppSelectionSourceButtonStyle(
                                tint: buttonTint(for: inputSource),
                                foreground: buttonForeground(for: inputSource)
                            )
                        )
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.74))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = item.icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(SettingsPalette.accentSoft.opacity(0.26))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "app.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SettingsPalette.accent)
                )
        }
    }

    private var borderColor: Color {
        if currentRule != nil {
            return SettingsPalette.accent.opacity(0.20)
        }

        if item.isFrontmost {
            return SettingsPalette.success.opacity(0.30)
        }

        return Color.white.opacity(0.84)
    }

    private func currentRuleBadgeTitle(for rule: AppRule) -> String {
        switch rule.policy {
        case .force:
            if
                let inputSourceID = rule.inputSourceId,
                let inputSource = availableInputSources.first(where: { $0.id == inputSourceID })
            {
                return inputSource.hudDetailName
            }
            return "FORCE"
        case .useGlobalDefault:
            return "GLOBAL"
        case .ignore:
            return "IGNORE"
        }
    }

    private func currentRuleBadgeTint(for rule: AppRule) -> Color {
        switch rule.policy {
        case .force:
            SettingsPalette.accent.opacity(0.82)
        case .useGlobalDefault:
            SettingsPalette.warning.opacity(0.88)
        case .ignore:
            SettingsPalette.slate.opacity(0.42)
        }
    }

    private func currentRuleBadgeForeground(for rule: AppRule) -> Color {
        switch rule.policy {
        case .force, .useGlobalDefault:
            .white
        case .ignore:
            SettingsPalette.ink
        }
    }

    private func buttonTint(for inputSource: InputSource) -> Color {
        if currentRule?.policy == .force, currentRule?.inputSourceId == inputSource.id {
            return SettingsPalette.accent
        }

        return inputSource.id == "com.apple.keylayout.ABC"
            ? SettingsPalette.accentSoft.opacity(0.28)
            : SettingsPalette.warning.opacity(0.20)
    }

    private func buttonForeground(for inputSource: InputSource) -> Color {
        if currentRule?.policy == .force, currentRule?.inputSourceId == inputSource.id {
            return .white
        }

        return SettingsPalette.ink
    }
}

private struct AppSelectionSourceButtonStyle: ButtonStyle {
    let tint: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.82 : 1.0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.72), lineWidth: 1)
            )
            .foregroundStyle(foreground)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
    }
}

private struct AppRuleRow: View {
    @Binding var rule: AppRule
    let availableInputSources: [InputSource]
    let onDelete: () -> Void

    var body: some View {
        SettingsSectionCard(
            title: rule.displayName,
            description: rule.bundleId,
            tint: policyTint
        ) {
            HStack(alignment: .center, spacing: 12) {
                SettingsPill(
                    text: policyBadgeTitle,
                    tint: policyTint.opacity(0.18),
                    foreground: SettingsPalette.ink
                )

                Spacer()

                Button("Delete", role: .destructive, action: onDelete)
                    .buttonStyle(SettingsGhostButtonStyle(tint: .red))
            }

            Divider()

            SettingsRow(
                title: "Display Name",
                description: "설정 창과 HUD에서 표시할 이름입니다.",
                accessoryWidth: 240
            ) {
                TextField("Display Name", text: $rule.displayName)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            SettingsRow(
                title: "Policy",
                description: "이 앱을 포그라운드로 전환했을 때 적용할 규칙입니다.",
                accessoryWidth: 240
            ) {
                Picker("", selection: policyBinding) {
                    ForEach(AppPolicy.allCases) { policy in
                        Text(policy.title)
                            .tag(policy)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            Divider()

            SettingsRow(
                title: "Forced Input Source",
                description: "정책이 `force`일 때 사용할 입력 소스입니다.",
                accessoryWidth: 240
            ) {
                Picker("", selection: inputSourceBinding) {
                    ForEach(availableInputSources) { inputSource in
                        Text(inputSource.localizedName)
                            .tag(inputSource.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(rule.policy != .force || availableInputSources.isEmpty)
            }

            if rule.policy == .force && availableInputSources.isEmpty {
                SettingsInfoCallout(
                    title: "No Input Sources Available",
                    message: "현재 macOS 입력 소스 목록에서 ABC 또는 두벌식을 찾지 못했습니다.",
                    symbolName: "exclamationmark.triangle.fill",
                    tint: SettingsPalette.warning
                )
            }
        }
    }

    private var policyBinding: Binding<AppPolicy> {
        Binding(
            get: { rule.policy },
            set: { newPolicy in
                rule.policy = newPolicy

                guard newPolicy == .force else {
                    return
                }

                if !availableInputSources.contains(where: { $0.id == rule.inputSourceId }) {
                    rule.inputSourceId = availableInputSources.first?.id
                }
            }
        )
    }

    private var inputSourceBinding: Binding<String> {
        Binding(
            get: {
                if
                    let savedID = rule.inputSourceId,
                    availableInputSources.contains(where: { $0.id == savedID })
                {
                    return savedID
                }

                return availableInputSources.first?.id ?? ""
            },
            set: { rule.inputSourceId = $0 }
        )
    }

    private var policyBadgeTitle: String {
        switch rule.policy {
        case .force:
            "FORCE"
        case .useGlobalDefault:
            "GLOBAL"
        case .ignore:
            "IGNORE"
        }
    }

    private var policyTint: Color {
        switch rule.policy {
        case .force:
            SettingsPalette.accent
        case .useGlobalDefault:
            SettingsPalette.warning
        case .ignore:
            SettingsPalette.slate
        }
    }
}
