import SwiftUI
import WidgetKit

@main
struct PocketVoiceApp: App {
    init() {
        UserDefaults.standard.register(defaults: [PocketVoiceShared.languageKey: "ko"])
        let currentLanguage = UserDefaults.standard.string(forKey: PocketVoiceShared.languageKey) ?? "ko"
        PocketVoiceShared.sharedDefaults?.register(defaults: [PocketVoiceShared.languageKey: currentLanguage])
        if PocketVoiceShared.sharedDefaults?.string(forKey: PocketVoiceShared.languageKey) == nil {
            PocketVoiceShared.sharedDefaults?.set(currentLanguage, forKey: PocketVoiceShared.languageKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    do {
                        try PocketVoiceStore.ensureContainerExists()
                        WidgetCenter.shared.reloadAllTimelines()
                    } catch {
                        PocketVoiceShared.appendLog("Launch setup failed: \(error.localizedDescription)")
                    }
                }
        }
    }
}
