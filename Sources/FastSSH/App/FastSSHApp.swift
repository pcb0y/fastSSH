import SwiftUI
import AppKit

@main
struct FastSSHApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var languageManager = LanguageManager.shared
    @StateObject private var aiConfig = AIConfigStore.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(languageManager)
                .environmentObject(aiConfig)
                .id(languageManager.currentLanguage)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("new.connection".localized) {
                    appState.showConnectionDialog = true
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Language") {
                ForEach(LanguageManager.supportedLanguages) { lang in
                    Button {
                        languageManager.currentLanguage = lang.id
                    } label: {
                        HStack {
                            Text(lang.name)
                            if languageManager.currentLanguage == lang.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register as a regular GUI app (needed for swift run)
        NSApplication.shared.setActivationPolicy(.regular)
        // Activate the app and bring it to front
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
