import SwiftUI

struct GeneralTab: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
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

                    Divider()

                    SettingsRow(
                        title: "Status",
                        description: "ServiceManagement가 보고한 현재 등록 상태입니다."
                    ) {
                        SettingsPill(
                            text: appEnvironment.launchAtLoginStatusDescription,
                            tint: launchStatusTint,
                            foreground: launchStatusForeground
                        )
                    }

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
}
