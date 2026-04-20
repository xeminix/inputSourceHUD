import SwiftUI

struct GeneralTab: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 24) {
                SettingsSectionHeader(
                    eyebrow: "GLOBAL",
                    title: "Automatic Switching",
                    description: "앱별 규칙이 없을 때 사용할 기본 입력 소스와 시작 동작을 관리합니다."
                )

                SettingsSectionCard(
                    title: "Global Policy",
                    description: "앱 전환 시 적용할 전역 동작을 정의합니다.",
                    tint: SettingsPalette.accent
                ) {
                    SettingsRow(
                        title: "Automatic Switching",
                        description: "포그라운드 앱이 바뀔 때 저장된 정책을 즉시 적용합니다."
                    ) {
                        Toggle("", isOn: $settingsStore.settings.global.enabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    Divider()

                    SettingsRow(
                        title: "Default Input Source",
                        description: "앱별 규칙이 없을 때 fallback으로 사용할 입력 소스입니다.",
                        accessoryWidth: 220
                    ) {
                        Picker("", selection: defaultInputSourceBinding) {
                            ForEach(appEnvironment.availableInputSources()) { inputSource in
                                Text(inputSource.localizedName)
                                    .tag(inputSource.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .disabled(appEnvironment.availableInputSources().isEmpty)
                    }
                }

                SettingsSectionCard(
                    title: "Startup and Session",
                    description: "로그인 항목과 현재 세션 상태를 관리합니다.",
                    tint: SettingsPalette.warning
                ) {
                    SettingsRow(
                        title: "Launch at Login",
                        description: "로그인 직후 menubar에서 자동으로 앱을 시작합니다."
                    ) {
                        Toggle("", isOn: $settingsStore.settings.global.launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    // Status 행은 사용자에게 불필요한 진단 정보라 UI에서 숨김.
                    // Divider()
                    // SettingsRow(
                    //     title: "Status",
                    //     description: "ServiceManagement가 보고한 현재 등록 상태입니다."
                    // ) {
                    //     SettingsPill(
                    //         text: appEnvironment.launchAtLoginStatusDescription,
                    //         tint: launchStatusTint,
                    //         foreground: launchStatusForeground
                    //     )
                    // }

                    if appEnvironment.launchAtLoginManager.currentStatus() == .requiresApproval {
                        SettingsInfoCallout(
                            title: "Approval Required",
                            message: "System Settings > Login Items에서 InputSourceHUD를 허용해야 자동 실행이 활성화됩니다.",
                            symbolName: "hand.raised.fill",
                            tint: SettingsPalette.warning
                        )
                    }

                    if appEnvironment.inputSourceManager.isSimulatedImplementation {
                        SettingsInfoCallout(
                            title: "Simulation Active",
                            message: "현재 빌드는 모의 입력 소스 매니저를 사용 중입니다. TIS 연동 확인이 필요합니다.",
                            symbolName: "exclamationmark.triangle.fill",
                            tint: SettingsPalette.warning
                        )
                    }
                }

                SettingsSectionCard(
                    title: "Live Shortcut Cycling",
                    description: "입력 메뉴의 다음/이전 소스 단축키를 누르는 동안 HUD를 각 스텝마다 즉시 갱신합니다.",
                    tint: SettingsPalette.success
                ) {
                    SettingsRow(
                        title: "Live Cycle HUD",
                        description: "Cmd+Space 또는 Control+Space 계열 순환 단축키를 길게 눌러도 HUD가 마지막 확정 전에 따라옵니다."
                    ) {
                        Toggle("", isOn: $settingsStore.settings.global.liveInputSourceCyclePreviewEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    // Status / Detected Shortcuts 는 사용자에게 불필요한 진단 정보라 UI에서 숨김.
                    // 향후 고급 옵션으로 복구할 수 있도록 코드는 주석으로 유지.
                    // Divider()
                    // SettingsRow(
                    //     title: "Status",
                    //     description: "현재 권한 및 단축키 감지 준비 상태입니다."
                    // ) {
                    //     SettingsPill(
                    //         text: liveCycleStatusText,
                    //         tint: liveCycleStatusTint,
                    //         foreground: liveCycleStatusForeground
                    //     )
                    // }
                    //
                    // if !appEnvironment.liveInputSourceCycleShortcuts.isEmpty {
                    //     Divider()
                    //     VStack(alignment: .leading, spacing: 10) {
                    //         Text("Detected Shortcuts")
                    //             .font(.system(size: 13, weight: .semibold, design: .rounded))
                    //             .foregroundStyle(SettingsPalette.ink)
                    //         LazyVGrid(
                    //             columns: [GridItem(.adaptive(minimum: 170), spacing: 8)],
                    //             alignment: .leading,
                    //             spacing: 8
                    //         ) {
                    //             ForEach(appEnvironment.liveInputSourceCycleShortcuts) { shortcut in
                    //                 SettingsPill(
                    //                     text: shortcut.displayLabel,
                    //                     tint: SettingsPalette.accentSoft.opacity(0.32),
                    //                     foreground: SettingsPalette.ink
                    //                 )
                    //             }
                    //         }
                    //     }
                    // }

                    switch appEnvironment.liveInputSourceCyclePredictionStatus {
                    case .requiresAccessibility:
                        Divider()

                        SettingsInfoCallout(
                            title: "Accessibility Permission Required",
                            message: "실시간 순환 HUD를 쓰려면 접근성 권한이 필요합니다. 권한을 허용한 뒤 Retry Detection을 누르면 바로 다시 붙습니다.",
                            symbolName: "keyboard.badge.eye",
                            tint: SettingsPalette.warning
                        )

                        HStack(spacing: 10) {
                            Button("Retry Detection") {
                                appEnvironment.refreshLiveInputSourceCyclePreview(promptIfNeeded: true)
                            }
                            .buttonStyle(SettingsProminentButtonStyle(tint: SettingsPalette.accent))

                            Button("Open Accessibility Settings") {
                                appEnvironment.openAccessibilitySettings()
                            }
                            .buttonStyle(SettingsGhostButtonStyle(tint: SettingsPalette.warning))
                        }

                    case .unavailableNoShortcuts:
                        Divider()

                        SettingsInfoCallout(
                            title: "No Cycle Shortcuts Enabled",
                            message: "macOS의 Keyboard Shortcuts > Input Sources에서 다음/이전 입력 소스 단축키를 켜야 실시간 순환 HUD가 동작합니다.",
                            symbolName: "command",
                            tint: SettingsPalette.warning
                        )

                    default:
                        EmptyView()
                    }
                }

                UpdateSettingsCard(updateController: appEnvironment.updateController)
            }
            .padding(30)
        }
    }

    private var defaultInputSourceBinding: Binding<String> {
        let availableInputSources = appEnvironment.availableInputSources()

        return Binding(
            get: {
                if
                    let savedID = settingsStore.settings.global.defaultInputSourceId,
                    availableInputSources.contains(where: { $0.id == savedID })
                {
                    return savedID
                }

                return availableInputSources.first?.id ?? ""
            },
            set: { newValue in
                settingsStore.settings.global.defaultInputSourceId = newValue
            }
        )
    }

    private var launchStatusTint: Color {
        switch appEnvironment.launchAtLoginManager.currentStatus() {
        case .enabled:
            SettingsPalette.success.opacity(0.88)
        case .requiresApproval:
            SettingsPalette.warning.opacity(0.88)
        case .notFound:
            SettingsPalette.steel.opacity(0.78)
        case .notRegistered:
            SettingsPalette.slate.opacity(0.60)
        @unknown default:
            SettingsPalette.slate.opacity(0.60)
        }
    }

    private var launchStatusForeground: Color {
        switch appEnvironment.launchAtLoginManager.currentStatus() {
        case .enabled, .requiresApproval:
            .white
        case .notFound, .notRegistered:
            SettingsPalette.ink
        @unknown default:
            SettingsPalette.ink
        }
    }

    private var liveCycleStatusText: String {
        switch appEnvironment.liveInputSourceCyclePredictionStatus {
        case .disabled:
            "Disabled"
        case .unavailableNoShortcuts:
            "No Shortcut"
        case .requiresAccessibility:
            "Needs Accessibility"
        case .active:
            "Live"
        }
    }

    private var liveCycleStatusTint: Color {
        switch appEnvironment.liveInputSourceCyclePredictionStatus {
        case .disabled:
            SettingsPalette.slate.opacity(0.60)
        case .unavailableNoShortcuts, .requiresAccessibility:
            SettingsPalette.warning.opacity(0.88)
        case .active:
            SettingsPalette.success.opacity(0.88)
        }
    }

    private var liveCycleStatusForeground: Color {
        switch appEnvironment.liveInputSourceCyclePredictionStatus {
        case .disabled:
            SettingsPalette.ink
        case .unavailableNoShortcuts, .requiresAccessibility, .active:
            .white
        }
    }
}

private struct UpdateSettingsCard: View {
    @ObservedObject var updateController: UpdateController

    var body: some View {
        SettingsSectionCard(
            title: "Updates",
            description: "Sparkle 기반 업데이트 확인과 릴리즈 배포 준비 상태를 관리합니다.",
            tint: SettingsPalette.accent
        ) {
            // Configuration / Appcast Feed / Last Update Event / Release Path Ready 는
            // 일반 사용자에게 불필요한 기술 정보라 UI에서 숨김. 향후 디버깅/관리 옵션으로
            // 복구할 수 있도록 코드는 주석으로 유지.
            // SettingsRow(
            //     title: "Configuration",
            //     description: "현재 appcast URL과 공개 EdDSA 키가 릴리즈 업데이트에 충분한지 보여줍니다."
            // ) {
            //     SettingsPill(
            //         text: updateController.configurationStatusText,
            //         tint: updateController.isConfigured
            //             ? SettingsPalette.success.opacity(0.88)
            //             : SettingsPalette.warning.opacity(0.88),
            //         foreground: .white
            //     )
            // }
            // Divider()
            // SettingsRow(
            //     title: "Appcast Feed",
            //     description: "Sparkle이 확인할 appcast.xml 주소입니다."
            // ) {
            //     Text(updateController.feedURLDisplayText)
            //         .font(.system(size: 11, weight: .semibold, design: .rounded))
            //         .foregroundStyle(SettingsPalette.steel.opacity(0.88))
            //         .multilineTextAlignment(.trailing)
            //         .frame(maxWidth: 260, alignment: .trailing)
            // }
            // Divider()

            SettingsRow(
                title: "Automatically Check for Updates",
                description: "백그라운드에서 주기적으로 새 버전을 확인합니다."
            ) {
                Toggle("", isOn: automaticallyChecksBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!updateController.isConfigured)
            }

            Divider()

            SettingsRow(
                title: "Automatically Download Updates",
                description: "새 버전을 찾았을 때 자동으로 내려받습니다."
            ) {
                Toggle("", isOn: automaticallyDownloadsBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!updateController.isConfigured || !updateController.automaticallyChecksForUpdates)
            }

            // Last Update Event — 내부 진단용이라 숨김
            // Divider()
            // SettingsRow(
            //     title: "Last Update Event",
            //     description: "최근 Sparkle 업데이트 세션 상태입니다."
            // ) {
            //     SettingsPill(
            //         text: updateController.lastUpdateEventText,
            //         tint: SettingsPalette.accentSoft.opacity(0.28),
            //         foreground: SettingsPalette.ink
            //     )
            // }

            Divider()

            HStack(spacing: 10) {
                Button("Check for Updates Now") {
                    updateController.checkForUpdates()
                }
                .buttonStyle(SettingsProminentButtonStyle(tint: SettingsPalette.accent))
                .disabled(!updateController.canPresentCheckForUpdates)

                // Release Setup Needed 뱃지 — 개발자 전용 정보라 숨김
                // if !updateController.isConfigured {
                //     SettingsPill(
                //         text: "Release Setup Needed",
                //         tint: SettingsPalette.warning.opacity(0.20),
                //         foreground: SettingsPalette.ink
                //     )
                // }
            }

            // Release Path Ready / Release Setup Required 콜아웃 — 개발자 진단용이라 숨김
            // SettingsInfoCallout(
            //     title: updateController.isConfigured ? "Release Path Ready" : "Release Setup Required",
            //     message: updateController.configurationHintText,
            //     symbolName: updateController.isConfigured ? "arrow.down.app.fill" : "shippingbox.fill",
            //     tint: updateController.isConfigured ? SettingsPalette.success : SettingsPalette.warning
            // )
        }
    }

    private var automaticallyChecksBinding: Binding<Bool> {
        Binding(
            get: { updateController.automaticallyChecksForUpdates },
            set: { updateController.setAutomaticallyChecksForUpdates($0) }
        )
    }

    private var automaticallyDownloadsBinding: Binding<Bool> {
        Binding(
            get: { updateController.automaticallyDownloadsUpdates },
            set: { updateController.setAutomaticallyDownloadsUpdates($0) }
        )
    }
}
