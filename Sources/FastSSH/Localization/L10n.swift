import Foundation
import SwiftUI

/// Manages app language, supporting manual override
@MainActor
class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    struct Language: Identifiable, Hashable {
        let id: String // locale code
        let name: String // native name
    }

    static let supportedLanguages: [Language] = [
        Language(id: "system", name: "System"),
        Language(id: "en", name: "English"),
        Language(id: "zh-Hans", name: "简体中文"),
        Language(id: "zh-Hant", name: "繁體中文"),
        Language(id: "ja", name: "日本語"),
        Language(id: "ko", name: "한국어"),
        Language(id: "es", name: "Español"),
        Language(id: "fr", name: "Français"),
        Language(id: "de", name: "Deutsch"),
        Language(id: "pt", name: "Português"),
        Language(id: "ru", name: "Русский"),
        Language(id: "ar", name: "العربية"),
        Language(id: "hi", name: "हिन्दी"),
    ]

    @Published var currentLanguage: String {
        didSet {
            UserDefaults.standard.set(currentLanguage, forKey: "AppLanguage")
            updateBundle()
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "AppLanguage") ?? "system"
        self.currentLanguage = saved
        updateBundle()
    }

    private func updateBundle() {
        let baseBundle = Bundle.module

        if currentLanguage == "system" {
            LocalizationBridge.current = baseBundle
            return
        }

        if let path = baseBundle.path(forResource: currentLanguage, ofType: "lproj"),
           let langBundle = Bundle(path: path) {
            LocalizationBridge.current = langBundle
        } else {
            LocalizationBridge.current = baseBundle
        }
    }
}

/// Thread-safe bridge for accessing localization bundle from any context
enum LocalizationBridge {
    nonisolated(unsafe) static var current: Bundle = Bundle.module
}

// Extend String for convenience
extension String {
    var localized: String {
        NSLocalizedString(self, bundle: LocalizationBridge.current, comment: "")
    }

    func localized(_ args: CVarArg...) -> String {
        let format = NSLocalizedString(self, bundle: LocalizationBridge.current, comment: "")
        return String(format: format, arguments: args)
    }
}
