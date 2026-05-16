import Foundation

public final class SettingsStore: @unchecked Sendable {
    public static let shared = SettingsStore()
    public static let defaultsSuiteName = "com.yurari.soundtranslator"
    public static let legacyDefaultsSuiteName = "com.gamst.soundtranslator"

    private let defaults: UserDefaults
    private let keyStore: APIKeyStore

    private enum Key {
        static let targetLanguage = "targetLanguage"
        static let selectedBundleIdentifier = "selectedBundleIdentifier"
        static let selectedProcessID = "selectedProcessID"
        static let captureSystemAudio = "captureSystemAudio"
        static let overlayOpacity = "overlayOpacity"
        static let overlayFontSize = "overlayFontSize"
        static let showDockIcon = "showDockIcon"
    }

    public init(
        defaults: UserDefaults = .standard,
        keyStore: APIKeyStore = KeychainClient(),
        legacyDefaults: UserDefaults? = nil
    ) {
        self.defaults = defaults
        self.keyStore = keyStore
        let migrationSource = legacyDefaults ?? (defaults === UserDefaults.standard ? UserDefaults(suiteName: Self.legacyDefaultsSuiteName) : nil)
        if let migrationSource {
            Self.migrateLegacyDefaults(from: migrationSource, to: defaults)
        }
    }

    public var targetLanguage: String {
        get {
            let stored = defaults.string(forKey: Key.targetLanguage) ?? "ko"
            return Self.supportedTargetLanguages.contains(stored) ? stored : "ko"
        }
        set {
            let sanitized = Self.supportedTargetLanguages.contains(newValue) ? newValue : "ko"
            defaults.set(sanitized, forKey: Key.targetLanguage)
        }
    }

    public var captureScope: CaptureScope {
        get {
            if defaults.bool(forKey: Key.captureSystemAudio) {
                return .system
            }
            if let bundleIdentifier = defaults.string(forKey: Key.selectedBundleIdentifier), !bundleIdentifier.isEmpty {
                let processID = Int32(defaults.integer(forKey: Key.selectedProcessID))
                if processID > 0 {
                    return .application(bundleIdentifier: bundleIdentifier, processID: processID)
                }
            }
            return .system
        }
        set {
            switch newValue {
            case .system:
                defaults.set(true, forKey: Key.captureSystemAudio)
                defaults.removeObject(forKey: Key.selectedBundleIdentifier)
                defaults.removeObject(forKey: Key.selectedProcessID)
            case let .application(bundleIdentifier, processID):
                defaults.set(false, forKey: Key.captureSystemAudio)
                defaults.set(bundleIdentifier, forKey: Key.selectedBundleIdentifier)
                defaults.set(Int(processID), forKey: Key.selectedProcessID)
            }
        }
    }

    public var overlayOpacity: Double {
        get {
            let value = defaults.double(forKey: Key.overlayOpacity)
            return value == 0 ? 0.82 : value
        }
        set { defaults.set(newValue, forKey: Key.overlayOpacity) }
    }

    public var overlayFontSize: Double {
        get {
            let value = defaults.double(forKey: Key.overlayFontSize)
            return value == 0 ? 30 : value
        }
        set { defaults.set(newValue, forKey: Key.overlayFontSize) }
    }

    public var showDockIcon: Bool {
        get {
            defaults.bool(forKey: Key.showDockIcon)
        }
        set {
            defaults.set(newValue, forKey: Key.showDockIcon)
        }
    }

    public func loadAPIKey() throws -> String? {
        try keyStore.loadAPIKey()
    }

    public func saveAPIKey(_ value: String) throws {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try keyStore.deleteAPIKey()
        } else {
            try keyStore.saveAPIKey(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static let supportedTargetLanguages = Set(TranslationLanguage.supported.map(\.id))

    private static func migrateLegacyDefaults(from legacyDefaults: UserDefaults, to defaults: UserDefaults) {
        let keys = [
            Key.targetLanguage,
            Key.selectedBundleIdentifier,
            Key.selectedProcessID,
            Key.captureSystemAudio,
            Key.overlayOpacity,
            Key.overlayFontSize,
            Key.showDockIcon
        ]

        for key in keys where defaults.object(forKey: key) == nil {
            guard let value = legacyDefaults.object(forKey: key) else {
                continue
            }
            defaults.set(value, forKey: key)
        }
    }
}
