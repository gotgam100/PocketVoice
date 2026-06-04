import SwiftUI
import WidgetKit

final class PocketVoiceAppModel: ObservableObject {
    @Published var autoplayRequestID: UUID?
    @Published var isShowingMiniPlayer = false
    @Published var selectedPersonID: String?

    func handle(url: URL) {
        guard url.scheme == "pocketvoice" else {
            PocketVoiceShared.appendLog("Ignored URL: \(url.absoluteString)")
            return
        }

        if url.host == "home" {
            isShowingMiniPlayer = false
            PocketVoiceShared.appendLog("Received widget URL for home")
            return
        }

        guard url.host == "play" else {
            PocketVoiceShared.appendLog("Ignored URL: \(url.absoluteString)")
            return
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        selectedPersonID = components?.queryItems?.first { $0.name == "person" }?.value
        isShowingMiniPlayer = true
        autoplayRequestID = UUID()
        PocketVoiceShared.appendLog("Received widget URL for person: \(selectedPersonID ?? "default")")
    }

    func showMiniPlayer(personID: String?) {
        selectedPersonID = personID
        isShowingMiniPlayer = true
        autoplayRequestID = UUID()
    }

    func closeMiniPlayer() {
        isShowingMiniPlayer = false
    }
}

@main
struct PocketVoiceApp: App {
    @StateObject private var appModel = PocketVoiceAppModel()

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
                .environmentObject(appModel)
                .onAppear {
                    do {
                        try PocketVoiceStore.ensureContainerExists()
                        WidgetCenter.shared.reloadAllTimelines()
                    } catch {
                        PocketVoiceShared.appendLog("Launch setup failed: \(error.localizedDescription)")
                    }
                }
                .onOpenURL { url in
                    appModel.handle(url: url)
                }
        }
    }
}
