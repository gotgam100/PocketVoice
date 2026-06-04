import AVFoundation
import ImageIO
import PhotosUI
import SwiftUI
import UIKit
import WidgetKit

private enum PocketVoiceFont {
    static func appTitle(_ size: CGFloat) -> Font {
        .custom("CWDangamAsac-Bold", size: size, relativeTo: .title)
    }

    static func title(_ size: CGFloat) -> Font {
        .custom("Paperlogy-7Bold", size: size, relativeTo: .title)
    }

    static func rounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Paperlogy-5Medium", size: size, relativeTo: .body).weight(weight)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }

    // Previous blue wave palette is preserved in AppBackground_Wave.imageset for easy rollback.
    static let pocketvoiceCream = Color(hex: 0xFFF3AF)
    static let pocketvoiceInk = Color(hex: 0x3A2500)
    static let pocketvoiceBlue = Color(hex: 0xEF2B24)
    static let pocketvoiceMuted = Color(hex: 0x8A6A1F)
    static let pocketvoiceCard = Color(hex: 0xFFF9D9)
    static let pocketvoiceYellow = Color(hex: 0xFFD400)
    static let pocketvoiceDeepYellow = Color(hex: 0xF5A900)
    static let pocketvoicePocket = Color(hex: 0xFFC928)
    static let pocketvoiceRed = Color(hex: 0xEF2B24)
    static let pocketvoiceRedDeep = Color(hex: 0xC91518)
}

private enum AppLanguage: String, CaseIterable, Identifiable {
    case korean = "ko"
    case english = "en"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .korean: "한국어"
        case .english: "English"
        }
    }
}

private enum AppText {
    static func value(_ key: Key, language rawValue: String) -> String {
        let language = AppLanguage(rawValue: rawValue) ?? .korean
        return switch (key, language) {
        case (.appName, .korean): "Pocket Voice"
        case (.appName, .english): "Pocket Voice"
        case (.tagline, .korean): "주머니 속 소중한 목소리."
        case (.tagline, .english): "Keep a voice in your pocket."
        case (.appInfo, .korean): "앱정보"
        case (.appInfo, .english): "App Info"
        case (.terms, .korean): "이용약관 및 정책"
        case (.terms, .english): "Terms & Policies"
        case (.language, .korean): "기본 언어"
        case (.language, .english): "Language"
        case (.name, .korean): "이름"
        case (.name, .english): "Name"
        case (.maxDuration, .korean): "최대 10초"
        case (.maxDuration, .english): "Up to 10 sec"
        case (.recorded, .korean): "녹음 완료"
        case (.recorded, .english): "Recorded"
        case (.recording, .korean): "녹음 중"
        case (.recording, .english): "Recording"
        case (.preview, .korean): "미리 듣기"
        case (.preview, .english): "Preview"
        case (.photoFailed, .korean): "사진 불러오기 실패"
        case (.photoFailed, .english): "Photo load failed"
        case (.photoAdded, .korean): "사진 등록"
        case (.photoAdded, .english): "Photo added"
        case (.photoAdjust, .korean): "사진 조절"
        case (.photoAdjust, .english): "Adjust photo"
        case (.widgetPrompt, .korean): "위젯으로 등록하여 목소리를 들어보세요"
        case (.widgetPrompt, .english): "Add voices to your widget and listen anytime."
        }
    }

    enum Key {
        case appName
        case tagline
        case appInfo
        case terms
        case language
        case name
        case maxDuration
        case recorded
        case recording
        case preview
        case photoFailed
        case photoAdded
        case photoAdjust
        case widgetPrompt
    }
}

struct ContentView: View {
    @EnvironmentObject private var appModel: PocketVoiceAppModel
    @State private var people = PocketVoiceStore.loadPeople()
    @State private var isShowingEditor = false
    @State private var editingPerson: PocketVoicePerson?
    @State private var status = ""
    @State private var isPlaying = false
    @State private var playingPersonID: String?
    @State private var playbackResetWorkItem: DispatchWorkItem?
    @State private var handledAutoplayRequestID: UUID?
    @State private var isShowingAppSettings = false
    @AppStorage("pocketvoice.language") private var languageRaw = AppLanguage.korean.rawValue

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundImage()

                if appModel.isShowingMiniPlayer {
                    MiniPlayerView(
                        person: selectedPerson,
                        isPlaying: isPlaying,
                        onPlayToggle: toggleSelectedPersonPlayback,
                        onClose: closeMiniPlayerAndStop
                    )
                } else {
                    homeView
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingEditor) {
                PersonEditorView(person: editingPerson) {
                    reloadPeople()
                }
            }
            .sheet(isPresented: $isShowingAppSettings) {
                AppSettingsView()
            }
            .onAppear {
                reloadPeople()
                handlePendingAutoplayIfNeeded()
            }
            .onChange(of: appModel.autoplayRequestID) { _, _ in
                handlePendingAutoplayIfNeeded()
            }
        }
    }

    private var selectedPerson: PocketVoicePerson? {
        PocketVoiceStore.person(id: appModel.selectedPersonID) ?? PocketVoiceStore.defaultPerson()
    }

    private var homeView: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 16) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppText.value(.appName, language: languageRaw))
                            .font(PocketVoiceFont.appTitle(34))
                            .foregroundStyle(Color.pocketvoiceInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .allowsTightening(true)
                        Text(AppText.value(.tagline, language: languageRaw))
                            .font(PocketVoiceFont.rounded(13, weight: .semibold))
                            .foregroundStyle(Color.pocketvoiceInk.opacity(0.72))
                    }

                    Spacer()

                    Button {
                        isShowingAppSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.pocketvoiceInk)
                            .frame(width: 48, height: 48)
                            .background(.white.opacity(0.38), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.48), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)

                if people.isEmpty {
                    emptyView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(people) { person in
                            PersonRow(person: person, isPlaying: playingPersonID == person.id) {
                                toggleListPlayback(person)
                            } onOpen: {
                                editingPerson = person
                                isShowingEditor = true
                            } onDelete: {
                                deletePerson(person)
                            } onReorder: { person, step in
                                movePerson(person, by: step)
                            } onReorderEnd: {
                                commitVisibleOrder()
                            }
                            }

                            Text(AppText.value(.widgetPrompt, language: languageRaw))
                                .font(PocketVoiceFont.rounded(14, weight: .semibold))
                                .foregroundStyle(Color.pocketvoiceInk.opacity(0.68))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 10)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 104)
                    }
                }
            }

            VStack(alignment: .trailing, spacing: 10) {
                Text("\(people.count)/\(PocketVoiceStore.maxPeople)")
                    .font(PocketVoiceFont.rounded(13, weight: .semibold))
                    .foregroundStyle(Color.pocketvoiceInk.opacity(0.78))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.48), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.58), lineWidth: 1))

                Button {
                    editingPerson = nil
                    isShowingEditor = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.pocketvoiceInk)
                        .frame(width: 64, height: 64)
                        .background(Color.pocketvoiceRed, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 1))
                        .shadow(color: Color.pocketvoiceRedDeep.opacity(0.32), radius: 18, y: 10)
                }
                .buttonStyle(.plain)
                .disabled(people.count >= PocketVoiceStore.maxPeople)
                .opacity(people.count >= PocketVoiceStore.maxPeople ? 0.35 : 1)
            }
            .padding(.trailing, 22)
            .padding(.bottom, 44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "person.crop.square.filled.and.at.rectangle")
                .font(.system(size: 58))
                .foregroundStyle(.white.opacity(0.86))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func reloadPeople() {
        people = PocketVoiceStore.loadPeople()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func movePerson(_ person: PocketVoicePerson, by step: Int) {
        guard step != 0, let currentIndex = people.firstIndex(of: person) else { return }
        let targetIndex = min(max(currentIndex + step, 0), people.count - 1)
        guard targetIndex != currentIndex else { return }

        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            let item = people.remove(at: currentIndex)
            people.insert(item, at: targetIndex)
        }
    }

    private func commitVisibleOrder() {
        var ordered = people
        for index in ordered.indices {
            ordered[index].sortOrder = index
        }
        do {
            try PocketVoiceStore.savePeople(ordered)
            reloadPeople()
        } catch {
            PocketVoiceShared.appendLog("Reorder failed: \(error.localizedDescription)")
        }
    }

    private func deletePerson(_ person: PocketVoicePerson) {
        do {
            try PocketVoiceStore.delete(person)
            reloadPeople()
        } catch {
            PocketVoiceShared.appendLog("Delete failed: \(error.localizedDescription)")
        }
    }

    private func handlePendingAutoplayIfNeeded() {
        guard let requestID = appModel.autoplayRequestID else {
            return
        }
        guard handledAutoplayRequestID != requestID else {
            return
        }
        handledAutoplayRequestID = requestID
        playSelectedPerson()
    }

    private func playSelectedPerson() {
        play(personID: selectedPerson?.id)
    }

    private func toggleSelectedPersonPlayback() {
        togglePlayback(personID: selectedPerson?.id)
    }

    private func toggleListPlayback(_ person: PocketVoicePerson) {
        togglePlayback(personID: person.id)
    }

    private func togglePlayback(personID: String?) {
        if isPlaying, playingPersonID == personID {
            stopPlayback()
            return
        }

        play(personID: personID)
    }

    private func play(personID: String?) {
        do {
            let duration = try PocketVoiceAudioPlayback.play(personID: personID)
            status = "playing"
            pulsePlaying(personID: personID, duration: duration)
        } catch {
            status = error.localizedDescription
            stopPlayback()
            PocketVoiceShared.appendLog("Playback failed: \(error.localizedDescription)")
        }
    }

    private func pulsePlaying(personID: String?, duration: TimeInterval) {
        playbackResetWorkItem?.cancel()
        playingPersonID = personID
        isPlaying = true

        let reset = DispatchWorkItem {
            guard playingPersonID == personID else {
                return
            }
            playingPersonID = nil
            isPlaying = false
        }
        playbackResetWorkItem = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + max(duration, 0.4), execute: reset)
    }

    private func stopPlayback() {
        playbackResetWorkItem?.cancel()
        playbackResetWorkItem = nil
        PocketVoiceAudioPlayback.stop()
        playingPersonID = nil
        isPlaying = false
    }

    private func closeMiniPlayerAndStop() {
        stopPlayback()
        appModel.closeMiniPlayer()
    }
}

private struct PersonRow: View {
    let person: PocketVoicePerson
    let isPlaying: Bool
    let onPlay: () -> Void
    let onOpen: () -> Void
    let onDelete: () -> Void
    let onReorder: (PocketVoicePerson, Int) -> Void
    let onReorderEnd: () -> Void
    @State private var horizontalOffset: CGFloat = 0
    @State private var dragYOffset: CGFloat = 0
    @State private var isReordering = false

    private let cardYellow = Color(hex: 0xFFD13A)
    private let cardDeepYellow = Color(hex: 0xF2A900)
    private let cardRed = Color(hex: 0xEF2B24)

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 72)
                    .background(Color(hex: 0xE11D48), in: RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            .opacity(isReordering ? 0 : 1)

            HStack(spacing: 13) {
                HStack(spacing: 13) {
                    PersonThumbnail(person: person, size: 62, radius: 16)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 7) {
                            Image(systemName: person.category.symbol)
                                .font(.caption)
                                .foregroundStyle(Color.pocketvoiceInk.opacity(0.62))
                            Text(person.name)
                                .font(PocketVoiceFont.rounded(17, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                                .layoutPriority(1)
                        }
                        .foregroundStyle(Color.pocketvoiceInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onOpen()
                }

                Button(action: onPlay) {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(cardRed, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.58), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.16), radius: 10, y: 5)
                }
                .buttonStyle(.plain)
                .disabled(!person.hasAudio)
                .opacity(person.hasAudio ? 1 : 0.35)

                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.pocketvoiceInk.opacity(0.54))
                    .frame(width: 34, height: 42)
                    .contentShape(Rectangle())
                    .highPriorityGesture(reorderGesture)
            }
            .padding(.vertical, 12)
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .background(
                LinearGradient(
                    colors: [cardYellow, cardDeepYellow],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 20)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.36), lineWidth: 1)
            }
            .shadow(color: Color(hex: 0xB97B00).opacity(0.22), radius: 18, y: 8)
            .offset(x: horizontalOffset)
            .gesture(
                DragGesture(minimumDistance: 18)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        horizontalOffset = max(min(value.translation.width, 0), -86)
                    }
                    .onEnded { value in
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
                            horizontalOffset = value.translation.width < -42 ? -86 : 0
                        }
                    }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .offset(y: dragYOffset * 0.16)
    }

    private var reorderGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard abs(value.translation.height) >= abs(value.translation.width) else { return }
                isReordering = true
                horizontalOffset = 0
                dragYOffset = value.translation.height
            }
            .onEnded { value in
                let rowDistance: CGFloat = 86
                let step = Int((value.translation.height / rowDistance).rounded(.toNearestOrAwayFromZero))

                withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                    dragYOffset = 0
                }
                isReordering = false

                if step != 0 {
                    onReorder(person, step)
                    onReorderEnd()
                }
            }
    }
}

private struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("pocketvoice.language") private var languageRaw = AppLanguage.korean.rawValue

    private var currentLanguage: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .korean
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Pocket Voice")
                            .font(PocketVoiceFont.appTitle(36))
                            .foregroundStyle(Color.pocketvoiceInk)
                        Text(AppText.value(.tagline, language: languageRaw))
                            .font(PocketVoiceFont.rounded(16, weight: .semibold))
                            .foregroundStyle(Color.pocketvoiceInk.opacity(0.74))
                    }
                    .padding(.top, 8)

                    settingsSection {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(AppText.value(.language, language: languageRaw))
                                .font(PocketVoiceFont.rounded(15, weight: .bold))
                                .foregroundStyle(Color.pocketvoiceInk)

                            HStack(spacing: 10) {
                                languageButton(.korean)
                                languageButton(.english)
                            }
                        }
                    }

                    settingsSection {
                        VStack(spacing: 0) {
                            settingsRow(
                                title: AppText.value(.appInfo, language: languageRaw),
                                value: currentLanguage == .korean ? "Pocket Voice" : "Pocket Voice",
                                systemImage: "info.circle.fill"
                            )

                            Divider()
                                .padding(.leading, 34)

                            settingsRow(
                                title: currentLanguage == .korean ? "앱버전" : "App Version",
                                value: appVersion,
                                systemImage: "number.circle.fill"
                            )

                            Divider()
                                .padding(.leading, 34)

                            policyLinkRow
                        }
                    }
                }
                .padding(22)
            }
            .background(Color.pocketvoiceCream)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.pocketvoiceInk)
                    }
                }
            }
        }
    }

    private func languageButton(_ language: AppLanguage) -> some View {
        let isSelected = languageRaw == language.rawValue
        return Button {
            languageRaw = language.rawValue
        } label: {
            Text(language.title)
                .font(PocketVoiceFont.rounded(15, weight: .bold))
                .foregroundStyle(isSelected ? .white : Color.pocketvoiceBlue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(isSelected ? Color.pocketvoiceBlue : .white, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(isSelected ? Color.pocketvoiceBlue : Color.pocketvoiceBlue.opacity(0.28), lineWidth: 1.4)
                }
                .shadow(color: isSelected ? Color.pocketvoiceBlue.opacity(0.22) : .clear, radius: 10, y: 5)
        }
        .buttonStyle(.plain)
    }

    private func settingsRow(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.pocketvoiceBlue)
                .frame(width: 22)
            Text(title)
                .font(PocketVoiceFont.rounded(16, weight: .semibold))
                .foregroundStyle(Color.pocketvoiceInk)
            Spacer()
            Text(value)
                .font(PocketVoiceFont.rounded(15, weight: .semibold))
                .foregroundStyle(Color.pocketvoiceMuted)
        }
        .padding(.vertical, 15)
    }

    private var policyLinkRow: some View {
        linkRow(
            title: AppText.value(.terms, language: languageRaw),
            systemImage: "doc.text.fill",
            url: policyURL
        )
    }

    private func linkRow(title: String, systemImage: String, url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.pocketvoiceBlue)
                    .frame(width: 22)
                Text(title)
                    .font(PocketVoiceFont.rounded(16, weight: .semibold))
                    .foregroundStyle(Color.pocketvoiceInk)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.pocketvoiceMuted)
            }
            .padding(.vertical, 15)
        }
        .buttonStyle(.plain)
    }

    private var policyURL: URL {
        if currentLanguage == .english {
            URL(string: "https://gotgam100.github.io/PocketVoice/en/")!
        } else {
            URL(string: "https://gotgam100.github.io/PocketVoice/")!
        }
    }

    private func settingsSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: Color(hex: 0x1A1A24).opacity(0.06), radius: 16, y: 7)
    }
}
private struct PersonThumbnail: View {
    let person: PocketVoicePerson
    let size: CGFloat
    var radius: CGFloat = 22

    var body: some View {
        Group {
            if let data = PocketVoiceStore.photoData(for: person), let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(Color(hex: person.category.accent.hex).opacity(0.16))
                    Text(String(person.name.prefix(1)))
                        .font(PocketVoiceFont.title(size * 0.55))
                        .foregroundStyle(Color(hex: person.category.accent.hex))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

private struct PersonEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = VoiceRecorder()
    @AppStorage("pocketvoice.language") private var languageRaw = AppLanguage.korean.rawValue

    let person: PocketVoicePerson?
    let onSave: () -> Void

    @State private var draftID: String
    @State private var name: String
    @State private var category: PocketVoiceCategory
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var cropImage: UIImage?
    @State private var isShowingPhotoCropper = false
    @State private var audioFileName: String?
    @State private var status: String
    @State private var isPreviewPlaying = false
    @State private var previewResetWorkItem: DispatchWorkItem?

    private var accent: Color {
        Color.pocketvoiceRed
    }

    init(person: PocketVoicePerson?, onSave: @escaping () -> Void) {
        self.person = person
        self.onSave = onSave
        _draftID = State(initialValue: person?.id ?? UUID().uuidString)
        _name = State(initialValue: person?.name ?? "")
        _category = State(initialValue: person?.category ?? .family)
        _photoData = State(initialValue: person.flatMap { PocketVoiceStore.photoData(for: $0) })
        _audioFileName = State(initialValue: person?.audioFileName)
        let savedLanguage = UserDefaults.standard.string(forKey: "pocketvoice.language") ?? AppLanguage.korean.rawValue
        _status = State(initialValue: AppText.value(.maxDuration, language: savedLanguage))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundImage()

                ScrollView {
                    VStack(spacing: 18) {
                        editorHeader
                        photoPicker
                        nameField
                        categoryPicker
                        recorderPanel
                    }
                    .padding(22)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: photoItem) { _, newItem in
                Task {
                    await loadPhoto(from: newItem)
                }
            }
            .sheet(isPresented: $isShowingPhotoCropper) {
                if let cropImage {
                    PhotoCropperView(image: cropImage, title: text(.photoAdjust), accent: accent) { data in
                        photoData = data
                        status = text(.photoAdded)
                        isShowingPhotoCropper = false
                    } onCancel: {
                        isShowingPhotoCropper = false
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                }
            }
            .onChange(of: recorder.isRecording) { _, isRecording in
                if !isRecording, recorder.lastRecordedURL != nil {
                    audioFileName = recorder.lastRecordedURL?.lastPathComponent
                    status = text(.recorded)
                }
            }
            .onAppear {
                if status == AppText.value(.maxDuration, language: AppLanguage.korean.rawValue)
                    || status == AppText.value(.maxDuration, language: AppLanguage.english.rawValue) {
                    status = text(.maxDuration)
                }
            }
        }
    }

    private func text(_ key: AppText.Key) -> String {
        AppText.value(key, language: languageRaw)
    }

    private var editorHeader: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.pocketvoiceInk)
                    .frame(width: 46, height: 46)
                    .background(Color.white.opacity(0.46), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                save()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.pocketvoiceMuted.opacity(0.65) : accent)
                    .frame(width: 48, height: 48)
                    .background(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.white.opacity(0.35) : Color.white,
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .shadow(color: Color(hex: 0x001A44).opacity(0.18), radius: 14, y: 7)
    }

    private var photoPicker: some View {
        VStack {
            PhotosPicker(selection: $photoItem, matching: .images, preferredItemEncoding: .compatible) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let photoData, let image = UIImage(data: photoData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            RoundedRectangle(cornerRadius: 26)
                                .fill(Color.white.opacity(0.56))
                                .overlay {
                                    Image(systemName: "photo.fill")
                                        .font(.system(size: 44))
                                        .foregroundStyle(Color.pocketvoiceMuted)
                                }
                        }
                    }
                    .frame(width: 176, height: 176)
                    .clipShape(RoundedRectangle(cornerRadius: 26))

                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(accent)
                        .frame(width: 46, height: 46)
                        .background(Color.white, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 4))
                        .offset(x: 4, y: 4)
                }
                .shadow(color: Color(hex: 0x001A44).opacity(0.12), radius: 18, y: 9)
                            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var nameField: some View {
        ZStack {
            if name.isEmpty {
                Text(text(.name))
                    .font(PocketVoiceFont.rounded(22, weight: .semibold))
                    .foregroundStyle(Color.pocketvoiceInk.opacity(0.48))
            }

            TextField("", text: $name)
                .font(PocketVoiceFont.rounded(22, weight: .semibold))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.never)
                .foregroundStyle(Color.pocketvoiceInk)
                .tint(accent)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 22)
        .background(Color.white, in: Capsule())
        .overlay {
            Capsule()
                .stroke(accent.opacity(0.20), lineWidth: 1)
        }
        .shadow(color: Color(hex: 0x001A44).opacity(0.10), radius: 13, y: 7)
        .frame(width: 176)
    }

    private var categoryPicker: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(48), spacing: 10), count: 3), spacing: 10) {
                ForEach(PocketVoiceCategory.allCases) { item in
                    Button {
                        category = item
                    } label: {
                        Image(systemName: item.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(category == item ? .white : Color.pocketvoiceInk.opacity(0.62))
                            .frame(width: 48, height: 48)
                            .background(
                                category == item ? accent : Color.white.opacity(0.48),
                                in: Circle()
                            )
                            .overlay {
                                Circle()
                                    .stroke(.white.opacity(category == item ? 0.95 : 0.28), lineWidth: category == item ? 3 : 1)
                            }
                            .shadow(color: Color.black.opacity(category == item ? 0.18 : 0.08), radius: category == item ? 14 : 5, y: category == item ? 8 : 3)
                        .accessibilityLabel(item.title)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 164)
        .padding(.vertical, 4)
    }

    private var recorderPanel: some View {
        VStack(spacing: 18) {
            HStack(spacing: 26) {
                CircleIconButton(
                    systemName: recorder.isRecording ? "stop.fill" : "mic.fill",
                    color: recorder.isRecording ? Color(hex: 0xEF4444) : Color.white,
                    iconColor: recorder.isRecording ? .white : accent,
                    size: 78,
                    action: toggleRecording
                )

                CircleIconButton(
                    systemName: isPreviewPlaying ? "stop.fill" : "play.fill",
                    color: Color.white,
                    iconColor: accent,
                    size: 68,
                    action: togglePreview
                )
                .disabled(audioFileName == nil && recorder.lastRecordedURL == nil)
                .opacity(audioFileName == nil && recorder.lastRecordedURL == nil ? 0.35 : 1)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.22))
                    Capsule()
                        .fill(Color.white)
                        .frame(width: proxy.size.width * min(recorder.elapsed / 10.0, 1.0))
                }
            }
            .frame(height: 12)
            .padding(.horizontal, 4)

            HStack(spacing: 8) {
                Image(systemName: recorder.isRecording ? "waveform" : "checkmark.seal.fill")
                Text(status)
                    .font(PocketVoiceFont.rounded(13, weight: .semibold))
            }
            .foregroundStyle(recorder.isRecording ? Color(hex: 0xEF4444) : accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Color.white, in: Capsule())
        }
        .padding(.top, 10)
    }

    private func toggleRecording() {
        if recorder.isRecording {
            recorder.stop()
            audioFileName = recorder.lastRecordedURL?.lastPathComponent
            status = text(.recorded)
            return
        }

        do {
            stopPreview()
            PocketVoiceAudioPlayback.stop()
            let url = PocketVoiceStore.audioURL(for: draftID)
            try recorder.start(url: url, maxDuration: 10.0)
            audioFileName = url.lastPathComponent
            status = text(.recording)
        } catch {
            status = error.localizedDescription
        }
    }

    private func togglePreview() {
        if isPreviewPlaying {
            stopPreview()
            return
        }

        playPreview()
    }

    private func playPreview() {
        do {
            let duration: TimeInterval
            if let url = recorder.lastRecordedURL {
                duration = try VoiceRecorder.play(url: url)
            } else if let audioFileName {
                duration = try VoiceRecorder.play(url: PocketVoiceStore.fileURL(audioFileName))
            } else {
                return
            }
            status = text(.preview)
            pulsePreview(duration: duration)
        } catch {
            status = error.localizedDescription
            stopPreview()
        }
    }

    private func pulsePreview(duration: TimeInterval) {
        previewResetWorkItem?.cancel()
        isPreviewPlaying = true

        let reset = DispatchWorkItem {
            isPreviewPlaying = false
        }
        previewResetWorkItem = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + max(duration, 0.4), execute: reset)
    }

    private func stopPreview() {
        previewResetWorkItem?.cancel()
        previewResetWorkItem = nil
        VoiceRecorder.stopPlayback()
        isPreviewPlaying = false
    }

    @MainActor
    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item else {
            return
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                status = text(.photoFailed)
                return
            }
            guard let image = UIImage(data: data)?.normalizedForPocketVoice() else {
                status = text(.photoFailed)
                return
            }
            cropImage = image
            isShowingPhotoCropper = true
        } catch {
            status = error.localizedDescription
        }
    }

    private func save() {
        do {
            stopPreview()
            let normalizedPhotoData = photoData.flatMap { normalizedPhotoPNGData(from: $0) ?? $0 }
            let savedPhotoFileName = try normalizedPhotoData.map { try PocketVoiceStore.savePhotoData($0, for: draftID) } ?? person?.photoFileName
            let updated = PocketVoicePerson(
                id: draftID,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category,
                accent: .sky,
                photoFileName: savedPhotoFileName,
                audioFileName: audioFileName ?? person?.audioFileName,
                createdAt: person?.createdAt ?? Date(),
                sortOrder: person?.sortOrder ?? 0
            )

            try PocketVoiceStore.upsert(updated)
            WidgetCenter.shared.reloadAllTimelines()
            onSave()
            dismiss()
        } catch {
            status = error.localizedDescription
        }
    }

    private func normalizedPhotoPNGData(from data: Data, maxPixelSize: CGFloat = 1_000) -> Data? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            return UIImage(data: data)?.pngData()
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return UIImage(data: data)?.pngData()
        }

        return UIImage(cgImage: cgImage).pngData()
    }
}

private struct PhotoCropperView: View {
    let image: UIImage
    let title: String
    let accent: Color
    let onComplete: (Data) -> Void
    let onCancel: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let frameSize: CGFloat = 300

    var body: some View {
        ZStack {
            AppBackgroundImage()

            VStack(spacing: 24) {
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.pocketvoiceInk)
                            .frame(width: 46, height: 46)
                            .background(Color.white.opacity(0.54), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text(title)
                        .font(PocketVoiceFont.rounded(18, weight: .bold))
                        .foregroundStyle(Color.pocketvoiceInk)

                    Spacer()

                    Button {
                        if let data = croppedPNGData() {
                            onComplete(data)
                        }
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(accent)
                            .frame(width: 48, height: 48)
                            .background(Color.white, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)

                Spacer(minLength: 8)

                ZStack {
                    RoundedRectangle(cornerRadius: 30)
                        .fill(Color.white.opacity(0.38))
                        .frame(width: frameSize + 18, height: frameSize + 18)

                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: frameSize, height: frameSize)
                            .scaleEffect(scale)
                            .offset(offset)
                    }
                    .frame(width: frameSize, height: frameSize)
                    .clipShape(RoundedRectangle(cornerRadius: 26))
                    .gesture(dragGesture.simultaneously(with: magnificationGesture))
                    .overlay {
                        RoundedRectangle(cornerRadius: 26)
                            .stroke(.white.opacity(0.92), lineWidth: 3)
                    }
                }
                .shadow(color: Color(hex: 0x3A2500).opacity(0.16), radius: 24, y: 12)

                HStack(spacing: 12) {
                    Image(systemName: "minus.magnifyingglass")
                    Slider(value: $scale, in: 1...3)
                        .tint(accent)
                        .onChange(of: scale) { _, _ in clampOffset() }
                    Image(systemName: "plus.magnifyingglass")
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.pocketvoiceInk.opacity(0.76))
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.52), in: Capsule())
                .padding(.horizontal, 28)

                Spacer()
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
                clampOffset()
            }
            .onEnded { _ in
                clampOffset()
                lastOffset = offset
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, 1), 3)
                clampOffset()
            }
            .onEnded { _ in
                scale = min(max(scale, 1), 3)
                lastScale = scale
                clampOffset()
                lastOffset = offset
            }
    }

    private func clampOffset() {
        let displayed = displayedImageSize()
        let maxX = max((displayed.width - frameSize) / 2, 0)
        let maxY = max((displayed.height - frameSize) / 2, 0)
        offset.width = min(max(offset.width, -maxX), maxX)
        offset.height = min(max(offset.height, -maxY), maxY)
    }

    private func displayedImageSize() -> CGSize {
        let imageSize = image.size
        let aspect = imageSize.width / max(imageSize.height, 1)
        let base: CGSize
        if aspect > 1 {
            base = CGSize(width: frameSize * aspect, height: frameSize)
        } else {
            base = CGSize(width: frameSize, height: frameSize / max(aspect, 0.01))
        }
        return CGSize(width: base.width * scale, height: base.height * scale)
    }

    private func croppedPNGData() -> Data? {
        guard let cgImage = image.cgImage else { return image.pngData() }
        let displayed = displayedImageSize()
        let originX = ((displayed.width - frameSize) / 2 - offset.width) / displayed.width
        let originY = ((displayed.height - frameSize) / 2 - offset.height) / displayed.height
        let widthRatio = frameSize / displayed.width
        let heightRatio = frameSize / displayed.height

        let pixelWidth = CGFloat(cgImage.width)
        let pixelHeight = CGFloat(cgImage.height)
        let x = min(max(originX * pixelWidth, 0), pixelWidth - 1)
        let y = min(max(originY * pixelHeight, 0), pixelHeight - 1)
        let cropRect = CGRect(
            x: x,
            y: y,
            width: min(widthRatio * pixelWidth, pixelWidth - x),
            height: min(heightRatio * pixelHeight, pixelHeight - y)
        ).integral

        guard cropRect.width > 1, cropRect.height > 1,
              let cropped = cgImage.cropping(to: cropRect) else { return image.pngData() }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1_000, height: 1_000))
        return renderer.pngData { _ in
            UIImage(cgImage: cropped).draw(in: CGRect(x: 0, y: 0, width: 1_000, height: 1_000))
        }
    }
}

private extension UIImage {
    func normalizedForPocketVoice() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private struct CircleIconButton: View {
    let systemName: String
    let color: Color
    var iconColor: Color = .white
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(iconColor)
                .frame(width: size, height: size)
                .background(color, in: Circle())
                .shadow(color: color.opacity(0.26), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }
}

private final class VoiceRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var elapsed = 0.0

    var lastRecordedURL: URL?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var maxDuration = 10.0
    private static var player: AVAudioPlayer?

    func start(url: URL, maxDuration: TimeInterval) throws {
        try PocketVoiceStore.ensureContainerExists()

        let session = AVAudioSession.sharedInstance()
        try session.setActive(false, options: [.notifyOthersOnDeactivation])
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.delegate = self
        recorder?.prepareToRecord()
        self.maxDuration = maxDuration
        elapsed = 0
        isRecording = true
        lastRecordedURL = url
        recorder?.record(forDuration: maxDuration)

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            elapsed = min(recorder?.currentTime ?? 0, self.maxDuration)
            if elapsed >= self.maxDuration {
                stop()
            }
        }
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        timer?.invalidate()
        timer = nil
        elapsed = maxDuration
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        isRecording = false
        elapsed = maxDuration
        timer?.invalidate()
        timer = nil
        self.recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    static func play(url: URL) throws -> TimeInterval {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try session.setActive(true)
        player = try AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        player?.play()
        return player?.duration ?? 0
    }

    static func stopPlayback() {
        player?.stop()
        player = nil
    }
}

private struct MiniPlayerView: View {
    let person: PocketVoicePerson?
    let isPlaying: Bool
    let onPlayToggle: () -> Void
    let onClose: () -> Void
    @AppStorage("pocketvoice.language") private var languageRaw = AppLanguage.korean.rawValue

    private var accent: Color {
        Color(hex: 0x22C55E)
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            if let person {
                PersonThumbnail(person: person, size: 170, radius: 38)
            } else {
                RoundedRectangle(cornerRadius: 38)
                    .fill(accent.opacity(0.18))
                    .frame(width: 170, height: 170)
            }

            Text(person?.name ?? AppText.value(.appName, language: languageRaw))
                .font(PocketVoiceFont.title(42))
                .foregroundStyle(.white)

            WaveformView(color: accent, isAnimating: isPlaying)
                .frame(width: 118, height: 34)
                .opacity(isPlaying ? 1 : 0.35)

            HStack(spacing: 22) {
                CircleIconButton(systemName: isPlaying ? "stop.fill" : "play.fill", color: accent, size: 62, action: onPlayToggle)
                CircleIconButton(systemName: "xmark", color: Color(hex: 0x27272A), size: 58, action: onClose)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                AppBackgroundImage()
            }
        }
    }
}

private struct AppBackgroundImage: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [Color(hex: 0xFFE04D), Color(hex: 0xFFC400), Color(hex: 0xF6A900)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(.white.opacity(0.16))
                    .frame(width: proxy.size.width * 0.92)
                    .blur(radius: 18)
                    .offset(x: proxy.size.width * 0.22, y: -proxy.size.height * 0.32)

                Circle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: proxy.size.width * 0.78)
                    .blur(radius: 24)
                    .offset(x: -proxy.size.width * 0.34, y: proxy.size.height * 0.32)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}






private struct WaveformView: View {
    let color: Color
    let isAnimating: Bool

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<7, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: 8, height: isAnimating ? CGFloat([16, 26, 20, 32, 18, 28, 14][index]) : 12)
                    .animation(
                        isAnimating
                        ? .easeInOut(duration: 0.48).repeatForever().delay(Double(index) * 0.06)
                        : .default,
                        value: isAnimating
                    )
            }
        }
    }
}
