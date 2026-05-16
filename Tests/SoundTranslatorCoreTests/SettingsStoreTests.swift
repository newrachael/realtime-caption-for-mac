import Foundation
import Testing
@testable import SoundTranslatorCore

private final class MemoryKeyStore: APIKeyStore, @unchecked Sendable {
    var value: String?

    func loadAPIKey() throws -> String? {
        value
    }

    func saveAPIKey(_ apiKey: String) throws {
        value = apiKey
    }

    func deleteAPIKey() throws {
        value = nil
    }
}

@Test func settingsPersistCaptureScope() throws {
    let defaults = UserDefaults(suiteName: "SoundTranslatorMacTests-\(UUID().uuidString)")!
    let keyStore = MemoryKeyStore()
    let store = SettingsStore(defaults: defaults, keyStore: keyStore)

    store.captureScope = .application(bundleIdentifier: "com.example.Player", processID: 1234)
    #expect(store.captureScope == .application(bundleIdentifier: "com.example.Player", processID: 1234))

    store.captureScope = .system
    #expect(store.captureScope == .system)
}

@Test func apiKeyUsesInjectedStore() throws {
    let defaults = UserDefaults(suiteName: "SoundTranslatorMacTests-\(UUID().uuidString)")!
    let keyStore = MemoryKeyStore()
    let store = SettingsStore(defaults: defaults, keyStore: keyStore)

    try store.saveAPIKey("  sk-test  ")
    #expect(try store.loadAPIKey() == "sk-test")

    try store.saveAPIKey("")
    #expect(try store.loadAPIKey() == nil)
}

@Test func settingsRejectUnsupportedTargetLanguage() throws {
    let defaults = UserDefaults(suiteName: "SoundTranslatorMacTests-\(UUID().uuidString)")!
    let keyStore = MemoryKeyStore()
    let store = SettingsStore(defaults: defaults, keyStore: keyStore)

    store.targetLanguage = "nl"
    #expect(store.targetLanguage == "ko")

    store.targetLanguage = "vi"
    #expect(store.targetLanguage == "vi")
}

@Test func settingsPersistDockVisibilityPreference() throws {
    let defaults = UserDefaults(suiteName: "SoundTranslatorMacTests-\(UUID().uuidString)")!
    let keyStore = MemoryKeyStore()
    let store = SettingsStore(defaults: defaults, keyStore: keyStore)

    #expect(store.showDockIcon == false)

    store.showDockIcon = true
    #expect(store.showDockIcon == true)

    store.showDockIcon = false
    #expect(store.showDockIcon == false)
}

@Test func settingsMigratesLegacyDefaultsWhenCurrentValuesAreMissing() throws {
    let defaults = UserDefaults(suiteName: "SoundTranslatorMacTests-\(UUID().uuidString)")!
    let legacyDefaults = UserDefaults(suiteName: "SoundTranslatorMacLegacyTests-\(UUID().uuidString)")!
    let keyStore = MemoryKeyStore()

    legacyDefaults.set("ja", forKey: "targetLanguage")
    legacyDefaults.set(false, forKey: "captureSystemAudio")
    legacyDefaults.set("com.example.Player", forKey: "selectedBundleIdentifier")
    legacyDefaults.set(4321, forKey: "selectedProcessID")
    legacyDefaults.set(0.65, forKey: "overlayOpacity")
    legacyDefaults.set(28.0, forKey: "overlayFontSize")
    legacyDefaults.set(true, forKey: "showDockIcon")

    let store = SettingsStore(defaults: defaults, keyStore: keyStore, legacyDefaults: legacyDefaults)

    #expect(store.targetLanguage == "ja")
    #expect(store.captureScope == .application(bundleIdentifier: "com.example.Player", processID: 4321))
    #expect(store.overlayOpacity == 0.65)
    #expect(store.overlayFontSize == 28.0)
    #expect(store.showDockIcon == true)
}
