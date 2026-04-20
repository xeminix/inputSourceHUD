import AppKit
import Foundation
import SwiftUI

struct AppSettings: Codable {
    var schemaVersion = 2
    var global = GlobalSettings()
    var hud = HUDSettings()
    var apps: [AppRule] = []
}

struct GlobalSettings: Codable {
    var enabled = true
    var defaultInputSourceId: String? = "com.apple.keylayout.ABC"
    var debounceMillis = 100
    var launchAtLogin = false
    var liveInputSourceCyclePreviewEnabled = true

    enum CodingKeys: String, CodingKey {
        case enabled
        case defaultInputSourceId
        case debounceMillis
        case launchAtLogin
        case liveInputSourceCyclePreviewEnabled
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        defaultInputSourceId = try container.decodeIfPresent(String.self, forKey: .defaultInputSourceId)
            ?? "com.apple.keylayout.ABC"
        debounceMillis = try container.decodeIfPresent(Int.self, forKey: .debounceMillis) ?? 100
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        liveInputSourceCyclePreviewEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .liveInputSourceCyclePreviewEnabled) ?? true
    }
}

struct CodableColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    init(_ nsColor: NSColor) {
        let c = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.red = Double(c.redComponent)
        self.green = Double(c.greenComponent)
        self.blue = Double(c.blueComponent)
        self.alpha = Double(c.alphaComponent)
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

struct HUDSettings: Codable {
    var enabled = true
    var showWhenAlreadyMatched = false
    var showOnManualInputSourceChange = true
    var durationSeconds = 1.0
    var backgroundOpacity: Double = 0.3
    var textOpacity: Double = 1.0
    var layout = HUDLayoutSettings()
    var backgroundColor: CodableColor? = nil
    var mainTextColor: CodableColor? = nil
    var identityTextColor: CodableColor? = nil
    var badgeTextColor: CodableColor? = nil
    var detailTextColor: CodableColor? = nil

    enum CodingKeys: String, CodingKey {
        case enabled
        case showWhenAlreadyMatched
        case showOnManualInputSourceChange
        case durationSeconds
        case backgroundOpacity
        case textOpacity
        case layout
        case backgroundColor
        case mainTextColor
        case identityTextColor
        case badgeTextColor
        case detailTextColor
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        showWhenAlreadyMatched =
            try container.decodeIfPresent(Bool.self, forKey: .showWhenAlreadyMatched) ?? false
        showOnManualInputSourceChange =
            try container.decodeIfPresent(Bool.self, forKey: .showOnManualInputSourceChange) ?? true
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 1.0
        backgroundOpacity = try container.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? 0.3
        textOpacity = try container.decodeIfPresent(Double.self, forKey: .textOpacity) ?? 1.0
        layout = try container.decodeIfPresent(HUDLayoutSettings.self, forKey: .layout) ?? HUDLayoutSettings()
        layout.normalizeUniquePositions()
        backgroundColor = try container.decodeIfPresent(CodableColor.self, forKey: .backgroundColor)
        mainTextColor = try container.decodeIfPresent(CodableColor.self, forKey: .mainTextColor)
        identityTextColor = try container.decodeIfPresent(CodableColor.self, forKey: .identityTextColor)
        badgeTextColor = try container.decodeIfPresent(CodableColor.self, forKey: .badgeTextColor)
        detailTextColor = try container.decodeIfPresent(CodableColor.self, forKey: .detailTextColor)
    }
}

enum HUDAccessoryKind: String, Codable, CaseIterable, Identifiable {
    case identity
    case badge
    case detail

    var id: String { rawValue }
}

enum HUDAnchorPosition: String, Codable, CaseIterable, Identifiable {
    case topLeading
    case topCenter
    case topTrailing
    case bottomLeading
    case bottomCenter
    case bottomTrailing

    var id: String { rawValue }
}

struct HUDAccessoryLayout: Codable, Hashable {
    var position: HUDAnchorPosition
    var isVisible: Bool = true
}

struct HUDLayoutSettings: Codable, Hashable {
    var identity = HUDAccessoryLayout(position: .topLeading, isVisible: true)
    var badge = HUDAccessoryLayout(position: .topTrailing, isVisible: true)
    var detail = HUDAccessoryLayout(position: .bottomCenter, isVisible: true)

    func accessory(for kind: HUDAccessoryKind) -> HUDAccessoryLayout {
        switch kind {
        case .identity:
            identity
        case .badge:
            badge
        case .detail:
            detail
        }
    }

    mutating func setAccessory(_ accessory: HUDAccessoryLayout, for kind: HUDAccessoryKind) {
        switch kind {
        case .identity:
            identity = accessory
        case .badge:
            badge = accessory
        case .detail:
            detail = accessory
        }
    }

    mutating func setVisibility(_ isVisible: Bool, for kind: HUDAccessoryKind) {
        var accessory = accessory(for: kind)
        accessory.isVisible = isVisible
        setAccessory(accessory, for: kind)
    }

    mutating func move(_ kind: HUDAccessoryKind, to position: HUDAnchorPosition) {
        let currentPosition = accessory(for: kind).position

        if let otherKind = HUDAccessoryKind.allCases.first(where: {
            $0 != kind && accessory(for: $0).position == position
        }) {
            var otherAccessory = accessory(for: otherKind)
            otherAccessory.position = currentPosition
            setAccessory(otherAccessory, for: otherKind)
        }

        var movingAccessory = accessory(for: kind)
        movingAccessory.position = position
        setAccessory(movingAccessory, for: kind)
    }

    mutating func normalizeUniquePositions() {
        let defaults: [HUDAccessoryKind: HUDAnchorPosition] = [
            .identity: .topLeading,
            .badge: .topTrailing,
            .detail: .bottomCenter
        ]

        var occupied = Set<HUDAnchorPosition>()

        for kind in HUDAccessoryKind.allCases {
            var accessory = accessory(for: kind)

            if occupied.contains(accessory.position) {
                accessory.position = defaults[kind] ?? .topLeading
            }

            if occupied.contains(accessory.position) {
                accessory.position = HUDAnchorPosition.allCases.first(where: { !occupied.contains($0) }) ?? .topLeading
            }

            occupied.insert(accessory.position)
            setAccessory(accessory, for: kind)
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            save()
        }
    }

    private let defaults: UserDefaults
    private let settingsKey = "com.codequa.inputSourceHUD.settings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if
            let data = defaults.data(forKey: settingsKey),
            let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(settings)
            defaults.set(data, forKey: settingsKey)
        } catch {
            Log.storage.error("Failed to save settings: \(error.localizedDescription, privacy: .public)")
        }
    }
}
