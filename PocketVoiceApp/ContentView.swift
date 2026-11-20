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
        case (.maxDurationPlus, .korean): "최대 1분"
        case (.maxDurationPlus, .english): "Up to 1 min"
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
        case (.photoAdjust, .korean): "사진꾸미기"
        case (.photoAdjust, .english): "Decorate photo"
        case (.emojiAdd, .korean): "이모티콘 추가"
        case (.emojiAdd, .english): "Add emoji"
        case (.widgetPreview, .korean): "위젯 미리보기"
        case (.widgetPreview, .english): "Widget preview"
        case (.widgetPrompt, .korean): "위젯으로 등록하여 목소리를 바로 들어보세요."
        case (.widgetPrompt, .english): "Add to widget and listen instantly."
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
        case maxDurationPlus
        case recorded
        case recording
        case preview
        case photoFailed
        case photoAdded
        case photoAdjust
        case emojiAdd
        case widgetPreview
        case widgetPrompt
    }
}

private enum PersonEditorRoute: Identifiable {
    case new
    case edit(PocketVoicePerson)

    var id: String {
        switch self {
        case .new:
            return "new-person"
        case .edit(let person):
            return person.id
        }
    }

    var person: PocketVoicePerson? {
        switch self {
        case .new:
            return nil
        case .edit(let person):
            return person
        }
    }
}

struct ContentView: View {
    @State private var people = PocketVoiceStore.loadPeople()
    @State private var editorRoute: PersonEditorRoute?
    @State private var isPlaying = false
    @State private var playingPersonID: String?
    @State private var playbackResetWorkItem: DispatchWorkItem?
    @State private var isShowingAppSettings = false
    @State private var isShowingPlus = false
    @ObservedObject private var plus = PocketVoicePlus.shared
    // Reordering: the row being dragged, how far the finger has moved, and
    // where that row started, so it can stay under the finger while others move.
    @State private var draggingID: String?
    @State private var dragTranslation: CGFloat = 0
    @State private var dragStartIndex = 0
    @State private var rowPitch: CGFloat = 98
    @State private var reorderSwaps = 0
    @State private var photoRevision = 0
    // Only one row shows a swipe action (pin on the left, delete on the right) at a time.
    @State private var openSwipe: OpenRowSwipe?
    @AppStorage(PocketVoiceShared.languageKey) private var languageRaw = AppLanguage.korean.rawValue

    private let rowSpacing: CGFloat = 12

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundImage()
                homeView
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editorRoute) { route in
                PersonEditorView(person: route.person) {
                    reloadPeople()
                }
            }
            .sheet(isPresented: $isShowingAppSettings) {
                AppSettingsView()
            }
            .sheet(isPresented: $isShowingPlus) {
                PocketVoicePlusView(reason: .peopleLimit)
            }
            .onAppear {
                reloadPeople()
            }
            .onReceive(NotificationCenter.default.publisher(for: PocketVoiceBackup.didRestoreNotification)) { _ in
                reloadPeople()
            }
        }
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
                        VStack(spacing: rowSpacing) {
                            ForEach(people) { person in
                                PersonRow(
                                    person: person,
                                    isPlaying: playingPersonID == person.id,
                                    isDragging: draggingID == person.id,
                                    dragOffset: draggingID == person.id ? draggedRowOffset : 0,
                                    photoRevision: photoRevision,
                                    openSide: swipeBinding(for: person),
                                    onPlay: { toggleListPlayback(person) },
                                    onOpen: { editorRoute = .edit(person) },
                                    onDelete: { deletePerson(person) },
                                    onTogglePin: { togglePin(person) },
                                    onReorderChanged: { reorderChanged(person, translation: $0) },
                                    onReorderEnded: reorderEnded
                                )
                                .zIndex(draggingID == person.id ? 1 : 0)
                                .transition(.asymmetric(insertion: .identity, removal: .opacity.combined(with: .scale(scale: 0.92))))
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                    rowPitch = height + rowSpacing
                                }
                            }

                            Text(AppText.value(.widgetPrompt, language: languageRaw))
                                .font(PocketVoiceFont.rounded(13, weight: .semibold))
                                .foregroundStyle(Color.pocketvoiceInk.opacity(0.68))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 10)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .padding(.bottom, 104)
                    }
                    .scrollDisabled(draggingID != nil)
                    .sensoryFeedback(.selection, trigger: reorderSwaps)
                    .sensoryFeedback(.impact(weight: .light), trigger: draggingID) { _, new in new != nil }
                }
            }

            VStack(alignment: .trailing, spacing: 10) {
                // Plus has no limit, so the counter only shows in the free version.
                if !plus.isActive {
                    Text("\(people.count)/\(PocketVoicePlus.freePeopleLimit)")
                        .font(PocketVoiceFont.rounded(13, weight: .semibold))
                        .foregroundStyle(Color.pocketvoiceInk.opacity(0.78))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.48), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.58), lineWidth: 1))
                }

                Button {
                    addPerson()
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

    /// Free users can keep everyone they already have (e.g. restored from a
    /// backup); only adding past the limit shows the Plus sheet.
    private func addPerson() {
        if plus.isActive || people.count < PocketVoicePlus.freePeopleLimit {
            editorRoute = .new
        } else {
            isShowingPlus = true
        }
    }

    private func reloadPeople() {
        people = PocketVoiceStore.loadPeople()
        // Photos keep the same file name when edited, so bump this to make
        // the list redraw thumbnails from disk.
        photoRevision += 1
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The dragged row's offset from its current slot, so it stays under the finger
    /// even after it has already swapped places with neighbors.
    private var draggedRowOffset: CGFloat {
        guard let draggingID, let index = people.firstIndex(where: { $0.id == draggingID }) else { return 0 }
        return dragTranslation - CGFloat(index - dragStartIndex) * rowPitch
    }

    private func swipeBinding(for person: PocketVoicePerson) -> Binding<RowSwipeSide?> {
        Binding(
            get: { openSwipe?.id == person.id ? openSwipe?.side : nil },
            set: { side in
                if let side {
                    openSwipe = OpenRowSwipe(id: person.id, side: side)
                } else if openSwipe?.id == person.id {
                    openSwipe = nil
                }
            }
        )
    }

    /// Pins to the very top, or unpins to just below the remaining pinned people.
    private func togglePin(_ person: PocketVoicePerson) {
        guard let index = people.firstIndex(where: { $0.id == person.id }) else { return }
        var reordered = people
        var moved = reordered.remove(at: index)
        moved.isPinned.toggle()
        let destination = moved.isPinned ? 0 : reordered.filter(\.isPinned).count
        reordered.insert(moved, at: destination)

        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            openSwipe = nil
            people = reordered
        }
        commitVisibleOrder()
    }

    private func reorderChanged(_ person: PocketVoicePerson, translation: CGFloat) {
        guard let currentIndex = people.firstIndex(where: { $0.id == person.id }) else { return }

        if draggingID == nil {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                openSwipe = nil
                draggingID = person.id
            }
            dragStartIndex = currentIndex
        }
        dragTranslation = translation

        // Swap as soon as the row passes the middle of its neighbor. Pinned and
        // unpinned people each reorder only within their own group.
        let pinnedCount = people.filter(\.isPinned).count
        let range = person.isPinned ? 0...(pinnedCount - 1) : pinnedCount...(people.count - 1)
        let targetIndex = min(max(dragStartIndex + Int((translation / rowPitch).rounded()), range.lowerBound), range.upperBound)
        guard targetIndex != currentIndex else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            people.move(
                fromOffsets: IndexSet(integer: currentIndex),
                toOffset: targetIndex > currentIndex ? targetIndex + 1 : targetIndex
            )
        }
        reorderSwaps += 1
    }

    private func reorderEnded() {
        guard draggingID != nil else { return }
        let changed = people.firstIndex(where: { $0.id == draggingID }) != dragStartIndex
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            draggingID = nil
            dragTranslation = 0
        }
        if changed {
            commitVisibleOrder()
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
            if playingPersonID == person.id {
                stopPlayback()
            }
            try PocketVoiceStore.delete(person)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                openSwipe = nil
                people.removeAll { $0.id == person.id }
            }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            PocketVoiceShared.appendLog("Delete failed: \(error.localizedDescription)")
        }
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
        Task {
            do {
                let duration = try await PocketVoiceAudioPlayback.play(personID: personID)
                pulsePlaying(personID: personID, duration: duration)
            } catch {
                stopPlayback()
                PocketVoiceShared.appendLog("Playback failed: \(error.localizedDescription)")
            }
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
}

private enum RowSwipeSide: Equatable {
    case pin
    case delete
}

private struct OpenRowSwipe: Equatable {
    let id: String
    let side: RowSwipeSide
}

/// Sideways swipe on a card that never blocks the list's vertical scrolling.
/// On iOS 18+ it uses a UIKit pan that only starts when the finger moves clearly
/// sideways, so up/down drags go straight to the scroll view.
private struct HorizontalSwipeModifier: ViewModifier {
    let isEnabled: Bool
    let onChanged: (CGFloat) -> Void
    let onEnded: (_ predictedEnd: CGFloat) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.gesture(
                HorizontalPanGesture(isEnabled: isEnabled, onChanged: onChanged, onEnded: onEnded)
            )
        } else {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .global)
                    .onChanged { value in
                        guard isEnabled, abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }
                        onChanged(value.translation.width)
                    }
                    .onEnded { value in
                        guard isEnabled else { return }
                        let sideways = abs(value.translation.width) > abs(value.translation.height) * 1.4
                        onEnded(sideways ? value.predictedEndTranslation.width : 0)
                    }
            )
        }
    }
}

@available(iOS 18.0, *)
private struct HorizontalPanGesture: UIGestureRecognizerRepresentable {
    let isEnabled: Bool
    let onChanged: (CGFloat) -> Void
    let onEnded: (_ predictedEnd: CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        // Window coordinates: the card moves under the finger, so its own
        // coordinates would shift while swiping and cause shaking.
        let translation = recognizer.translation(in: nil).x
        switch recognizer.state {
        case .changed:
            onChanged(translation)
        case .ended:
            let velocity = recognizer.velocity(in: nil).x
            onEnded(translation + velocity * 0.15)
        case .cancelled, .failed:
            onEnded(translation)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Start only for a clearly sideways move; anything else is scrolling.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: nil)
            return abs(velocity.x) > abs(velocity.y) * 1.4
        }
    }
}

private struct PersonRow: View {
    let person: PocketVoicePerson
    let isPlaying: Bool
    let isDragging: Bool
    let dragOffset: CGFloat
    let photoRevision: Int
    @Binding var openSide: RowSwipeSide?
    let onPlay: () -> Void
    let onOpen: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void
    let onReorderChanged: (CGFloat) -> Void
    let onReorderEnded: () -> Void

    /// Live horizontal finger movement while swiping to reveal an action.
    @State private var swipeTranslation: CGFloat = 0

    private let cardYellow = Color(hex: 0xFFD13A)
    private let cardDeepYellow = Color(hex: 0xF2A900)
    private let cardRed = Color(hex: 0xEF2B24)
    private let deleteRed = Color(hex: 0xE11D48)
    private let pinOrange = Color(hex: 0xFF7A00)
    private let actionWidth: CGFloat = 88

    private var restingOffset: CGFloat {
        switch openSide {
        case .pin: actionWidth
        case .delete: -actionWidth
        case nil: 0
        }
    }

    /// Where the card sits: follows the finger, with a soft stop past each button.
    /// With one side open, the card can only travel back to the center; the
    /// other side opens only with a new swipe from the closed position.
    private var cardOffset: CGFloat {
        var raw = restingOffset + swipeTranslation
        switch openSide {
        case .delete: raw = min(raw, 0)
        case .pin: raw = max(raw, 0)
        case nil: break
        }
        if raw > actionWidth {
            return actionWidth + (raw - actionWidth) * 0.3
        }
        if raw < -actionWidth {
            return -actionWidth + (raw + actionWidth) * 0.3
        }
        return raw
    }

    private let actionGap: CGFloat = 8

    /// Each action button is exactly as wide as the space the card has moved
    /// out of (minus a small gap), so the card and button never overlap or fade.
    private var pinButtonWidth: CGFloat {
        max(cardOffset - actionGap, 0)
    }

    private var deleteButtonWidth: CGFloat {
        max(-cardOffset - actionGap, 0)
    }

    var body: some View {
        ZStack {
            card
                .offset(x: cardOffset)
            // In front of the card, so the card's shadow never dims the buttons.
            HStack(spacing: 0) {
                pinButton
                Spacer(minLength: 0)
                deleteButton
            }
        }
        .scaleEffect(isDragging ? 1.03 : 1)
        .shadow(color: Color(hex: 0x7A4B00).opacity(isDragging ? 0.28 : 0), radius: 22, y: 14)
        .offset(y: dragOffset)
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            VStack(spacing: 4) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 18, weight: .bold))
                Text(PocketVoiceShared.isEnglish ? "Delete" : "삭제")
                    .font(PocketVoiceFont.rounded(12, weight: .bold))
            }
            .foregroundStyle(.white)
            .fixedSize()
            .frame(width: deleteButtonWidth)
            .frame(maxHeight: .infinity)
            .background(deleteRed)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(openSide == .delete)
        .accessibilityHidden(openSide != .delete)
    }

    private var pinButton: some View {
        Button(action: onTogglePin) {
            VStack(spacing: 4) {
                Image(systemName: person.isPinned ? "pin.slash.fill" : "pin.fill")
                    .font(.system(size: 18, weight: .bold))
                Text(pinTitle)
                    .font(PocketVoiceFont.rounded(12, weight: .bold))
            }
            .foregroundStyle(.white)
            .fixedSize()
            .frame(width: pinButtonWidth)
            .frame(maxHeight: .infinity)
            .background(pinOrange)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(openSide == .pin)
        .accessibilityHidden(openSide != .pin)
    }

    private var pinTitle: String {
        if PocketVoiceShared.isEnglish {
            return person.isPinned ? "Unpin" : "Favorite"
        }
        return person.isPinned ? "해제" : "최애"
    }

    private var card: some View {
        HStack(spacing: 13) {
            HStack(spacing: 13) {
                PersonThumbnail(person: person, size: 62, radius: 16)
                    .id(photoRevision)

                HStack(spacing: 7) {
                    Image(systemName: person.category.symbol)
                        .font(.caption)
                        .foregroundStyle(Color.pocketvoiceInk.opacity(0.62))
                    Text(person.name)
                        .font(PocketVoiceFont.rounded(17, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .layoutPriority(1)
                    if person.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(cardRed)
                            .rotationEffect(.degrees(35))
                            .accessibilityLabel(PocketVoiceShared.isEnglish ? "Pinned" : "최애 고정")
                    }
                }
                .foregroundStyle(Color.pocketvoiceInk)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if openSide != nil {
                    closeSwipe()
                } else {
                    onOpen()
                }
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
                .foregroundStyle(Color.pocketvoiceInk.opacity(isDragging ? 0.85 : 0.54))
                .frame(width: 40, height: 62)
                .contentShape(Rectangle())
                // Global space: the row itself moves while dragging, so local
                // coordinates would shift under the finger and cause jitter.
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { onReorderChanged($0.translation.height) }
                        .onEnded { _ in onReorderEnded() }
                )
                .accessibilityLabel(PocketVoiceShared.isEnglish ? "Reorder" : "순서 변경")
        }
        .padding(.vertical, 12)
        .padding(.leading, 14)
        .padding(.trailing, 6)
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
        .modifier(HorizontalSwipeModifier(
            isEnabled: !isDragging,
            onChanged: { swipeTranslation = $0 },
            onEnded: finishSwipe
        ))
    }

    /// `predictedEnd` is where the swipe was heading, so a quick flick also opens or closes.
    private func finishSwipe(predictedEnd: CGFloat) {
        let projected = restingOffset + predictedEnd
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            switch openSide {
            case .delete:
                // Stay open or close; never jump straight to the pin side.
                openSide = projected < -actionWidth / 2 ? .delete : nil
            case .pin:
                openSide = projected > actionWidth / 2 ? .pin : nil
            case nil:
                if projected < -actionWidth / 2 {
                    openSide = .delete
                } else if projected > actionWidth / 2 {
                    openSide = .pin
                }
            }
            swipeTranslation = 0
        }
    }

    private func closeSwipe() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            openSide = nil
        }
    }
}

private struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(PocketVoiceShared.languageKey) private var languageRaw = AppLanguage.korean.rawValue
    // Stored in the shared App Group defaults so widget playback uses it too.
    @AppStorage(PocketVoiceShared.volumeKey, store: PocketVoiceShared.sharedDefaults) private var appVolume = 1.0
    @ObservedObject private var plus = PocketVoicePlus.shared
    @State private var isShowingPlus = false
    @State private var lastBackupDate = PocketVoiceBackup.lastBackupDate

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
                        // Same as the main screen title. A plain Text("Pocket Voice") was
                        // translated by the iPhone's system language, not the app's language.
                        Text(AppText.value(.appName, language: languageRaw))
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
                        plusSection
                    }

                    settingsSection {
                        volumeControl
                    }

                    settingsSection {
                        backupSection
                    }

                    settingsSection {
                        VStack(spacing: 0) {
                            settingsRow(
                                title: AppText.value(.appInfo, language: languageRaw),
                                value: "Pocket Voice",
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

                            Divider()
                                .padding(.leading, 34)

                            linkRow(
                                title: currentLanguage == .korean ? "개발자의 다른 앱" : "More Apps by Developer",
                                systemImage: "square.grid.2x2.fill",
                                url: developerAppsURL
                            )
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
            .sheet(isPresented: $isShowingPlus) {
                PocketVoicePlusView(reason: .settings)
            }
            .onAppear {
                lastBackupDate = PocketVoiceBackup.lastBackupDate
            }
        }
    }

    private var isKorean: Bool {
        currentLanguage == .korean
    }

    private var plusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.pocketvoiceBlue)
                Text("Pocket Voice Plus")
                    .font(PocketVoiceFont.rounded(15, weight: .bold))
                    .foregroundStyle(Color.pocketvoiceInk)
                Spacer()
                if plus.isActive {
                    Text(isKorean ? "사용 중" : "Active")
                        .font(PocketVoiceFont.rounded(13, weight: .bold))
                        .foregroundStyle(Color.pocketvoiceBlue)
                }
            }

            Text(plusDescription)
                .font(PocketVoiceFont.rounded(12, weight: .medium))
                .foregroundStyle(Color.pocketvoiceInk.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            if !plus.isActive {
                Button {
                    isShowingPlus = true
                } label: {
                    Text(isKorean
                         ? "\(plus.displayPrice)에 구매하기"
                         : "Buy for \(plus.displayPrice)")
                        .font(PocketVoiceFont.rounded(15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.pocketvoiceBlue, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var plusDescription: String {
        if plus.isEarlyUser && !plus.isPurchased {
            return isKorean
                ? "기존 사용자 혜택으로 무료로 사용 중이에요. 인물 수 제한 없이, 최대 1분까지 녹음할 수 있어요."
                : "Free for you as an early user. Add as many people as you like and record up to 1 minute."
        }
        if plus.isActive {
            return isKorean
                ? "인물 수 제한 없이, 최대 1분까지 녹음할 수 있어요."
                : "Add as many people as you like and record up to 1 minute."
        }
        return isKorean
            ? "한 번 구매로 인물 수 제한을 풀고, 최대 1분까지 녹음할 수 있어요. (무료: 4명, 10초)"
            : "One purchase removes the people limit and lets you record up to 1 minute. (Free: 4 people, 10 sec)"
    }

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "icloud.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.pocketvoiceBlue)
                Text(isKorean ? "iCloud 자동 백업" : "iCloud Auto Backup")
                    .font(PocketVoiceFont.rounded(15, weight: .bold))
                    .foregroundStyle(Color.pocketvoiceInk)
                Spacer()
                if PocketVoiceBackup.isICloudSignedIn {
                    Text(isKorean ? "켜짐" : "On")
                        .font(PocketVoiceFont.rounded(13, weight: .bold))
                        .foregroundStyle(Color.pocketvoiceBlue)
                }
            }

            if PocketVoiceBackup.isICloudSignedIn {
                Text(backupStatusText)
                    .font(PocketVoiceFont.rounded(13, weight: .semibold))
                    .foregroundStyle(Color.pocketvoiceMuted)
            }

            Text(PocketVoiceBackup.isICloudSignedIn
                 ? (isKorean
                    ? "앱을 닫을 때 바뀐 내용을 내 iCloud에 자동으로 백업해요. 같은 Apple 계정의 다른 iPhone에서 앱을 열면 자동으로 불러와요. iCloud 저장 공간을 사용해요."
                    : "Changes are backed up to your iCloud when you leave the app, and load automatically when you open the app on another iPhone with the same Apple Account. Uses your iCloud storage.")
                 : (isKorean
                    ? "iPhone 설정에서 iCloud에 로그인하고 iCloud Drive를 켜면 자동으로 백업돼요."
                    : "Sign in to iCloud and turn on iCloud Drive in Settings to back up automatically."))
                .font(PocketVoiceFont.rounded(12, weight: .medium))
                .foregroundStyle(Color.pocketvoiceInk.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var backupStatusText: String {
        guard let date = lastBackupDate else {
            return isKorean ? "아직 백업 전이에요" : "Not backed up yet"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: isKorean ? "ko_KR" : "en_US")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let when = formatter.string(from: date)
        return isKorean ? "마지막 백업: \(when)" : "Last backup: \(when)"
    }

    private var volumeControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(currentLanguage == .korean ? "앱 볼륨" : "App Volume")
                    .font(PocketVoiceFont.rounded(15, weight: .bold))
                    .foregroundStyle(Color.pocketvoiceInk)
                Spacer()
                Text("\(Int((appVolume * 100).rounded()))%")
                    .font(PocketVoiceFont.rounded(15, weight: .semibold))
                    .foregroundStyle(Color.pocketvoiceMuted)
                    .monospacedDigit()
            }

            HStack(spacing: 12) {
                Image(systemName: appVolume == 0 ? "speaker.slash.fill" : "speaker.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.pocketvoiceBlue)
                    .frame(width: 20)
                Slider(value: $appVolume, in: 0...1, step: 0.05)
                    .tint(Color.pocketvoiceBlue)
                    .accessibilityLabel(currentLanguage == .korean ? "앱 볼륨" : "App Volume")
                    .accessibilityValue("\(Int((appVolume * 100).rounded()))%")
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.pocketvoiceBlue)
            }
            .onChange(of: appVolume) { _, _ in
                PocketVoiceAudioPlayback.applyVolume()
                VoiceRecorder.applyVolume()
            }

            Text(currentLanguage == .korean
                 ? "아이폰 볼륨을 기준으로, 앱과 위젯에서 나오는 목소리 크기를 조절해요."
                 : "Sets how loud voices play in the app and widget, relative to your iPhone volume.")
                .font(PocketVoiceFont.rounded(12, weight: .medium))
                .foregroundStyle(Color.pocketvoiceInk.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func languageButton(_ language: AppLanguage) -> some View {
        let isSelected = languageRaw == language.rawValue
        return Button {
            languageRaw = language.rawValue
            PocketVoiceShared.setLanguage(language.rawValue)
            WidgetCenter.shared.reloadAllTimelines()
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

    // Seunghwa Baek's developer page; on iPhone this opens in the App Store app.
    private var developerAppsURL: URL {
        URL(string: "https://apps.apple.com/developer/id1892791489")!
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
    @ObservedObject private var plus = PocketVoicePlus.shared
    @AppStorage(PocketVoiceShared.languageKey) private var languageRaw = AppLanguage.korean.rawValue

    let person: PocketVoicePerson?
    let onSave: () -> Void

    @State private var draftID: String
    @State private var name: String
    @State private var category: PocketVoiceCategory
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var sourcePhotoData: Data?
    @State private var photoDecoration: PocketVoicePhotoDecoration
    @State private var cropImage: UIImage?
    @State private var isShowingPhotoCropper = false
    @State private var audioFileName: String?
    @State private var status: String
    @State private var isPreviewPlaying = false
    @State private var previewResetWorkItem: DispatchWorkItem?
    @State private var isSaving = false
    @FocusState private var isNameFocused: Bool
    @State private var savedLevels: [Float] = []
    @State private var previewStartedAt: Date?
    @State private var previewDuration: TimeInterval = 0

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
        _sourcePhotoData = State(initialValue: person.flatMap { PocketVoiceStore.sourcePhotoData(for: $0) } ?? person.flatMap { PocketVoiceStore.photoData(for: $0) })
        _photoDecoration = State(initialValue: person?.photoDecoration ?? .empty)
        _audioFileName = State(initialValue: person?.audioFileName)
        let savedLanguage = UserDefaults.standard.string(forKey: "pocketvoice.language") ?? AppLanguage.korean.rawValue
        _status = State(initialValue: AppText.value(PocketVoicePlus.cachedIsActive ? .maxDurationPlus : .maxDuration, language: savedLanguage))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundImage()

                // Tapping any empty spot (around or below the form) hides the keyboard.
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { isNameFocused = false }

                ScrollView {
                    VStack(spacing: 18) {
                        editorHeader
                        photoPicker
                        nameField
                        categoryPicker
                        recorderPanel
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity)
                    .background {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { isNameFocused = false }
                    }
                }
                .scrollDismissesKeyboard(.immediately)
                .disabled(isShowingPhotoCropper)

                if isShowingPhotoCropper, let cropImage {
                    PhotoCropperView(
                        image: cropImage,
                        title: text(.photoAdjust),
                        accent: accent,
                        initialDecoration: photoDecoration
                    ) { data, decoration in
                        photoData = data
                        sourcePhotoData = cropImage.pngData()
                        photoDecoration = decoration
                        status = text(.photoAdded)
                        isShowingPhotoCropper = false
                    } onCancel: {
                        isShowingPhotoCropper = false
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(2)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: photoItem) { _, newItem in
                Task {
                    await loadPhoto(from: newItem)
                }
            }
            .onChange(of: recorder.isRecording) { _, isRecording in
                if !isRecording, let url = recorder.lastRecordedURL {
                    status = text(.recorded)
                    // Redraw the finished recording across the whole width.
                    Task {
                        await PocketVoiceAudioSession.waitForPendingWork()
                        let levels = await VoiceWaveform.levels(for: url)
                        if !levels.isEmpty, !recorder.isRecording {
                            recorder.levels = levels
                        }
                    }
                }
            }
            .onDisappear(perform: cleanUpOnClose)
            .task {
                if let audioFileName {
                    savedLevels = await VoiceWaveform.levels(for: PocketVoiceStore.fileURL(audioFileName))
                }
            }
            .onAppear {
                let hints = [AppText.Key.maxDuration, .maxDurationPlus].flatMap { key in
                    AppLanguage.allCases.map { AppText.value(key, language: $0.rawValue) }
                }
                if hints.contains(status) {
                    status = text(durationHintKey)
                }
            }
        }
    }

    private func text(_ key: AppText.Key) -> String {
        AppText.value(key, language: languageRaw)
    }

    private var durationHintKey: AppText.Key {
        plus.isActive ? .maxDurationPlus : .maxDuration
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
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
        }
        .shadow(color: Color(hex: 0x001A44).opacity(0.18), radius: 14, y: 7)
    }

    private var photoPicker: some View {
        VStack(spacing: 10) {
            Text(text(.widgetPreview))
                .font(PocketVoiceFont.rounded(12, weight: .bold))
                .foregroundStyle(Color.pocketvoiceInk.opacity(0.62))

            PhotosPicker(selection: $photoItem, matching: .images, preferredItemEncoding: .compatible) {
                widgetPhotoPreview
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var widgetPhotoPreview: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ZStack {
                Group {
                    if let photoData, let image = UIImage(data: photoData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 28)
                            .fill(Color.white.opacity(0.56))
                            .overlay {
                                Image(systemName: "photo.fill")
                                    .font(.system(size: 42))
                                    .foregroundStyle(Color.pocketvoiceMuted)
                            }
                    }
                }
                .frame(width: photoPreviewSize.width, height: photoPreviewSize.height)

                VStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.94))
                        .frame(width: 58, height: 18)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()

                    HStack {
                        Spacer()
                        Circle()
                            .fill(Color.white.opacity(0.96))
                            .frame(width: 42, height: 42)
                    }
                }
                .padding(12)
            }
            .frame(width: photoPreviewSize.width, height: photoPreviewSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.72), lineWidth: 1))
            .shadow(color: Color(hex: 0x3A2500).opacity(0.16), radius: 20, y: 10)
            .contentShape(RoundedRectangle(cornerRadius: 28))

            if photoData != nil {
                Button {
                    let editableData = sourcePhotoData ?? photoData
                    if let editableData, let image = UIImage(data: editableData)?.normalizedForPocketVoice() {
                        cropImage = image
                        isShowingPhotoCropper = true
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "wand.and.sparkles")
                            .font(.system(size: 12, weight: .bold))
                        Text(text(.photoAdjust))
                            .font(PocketVoiceFont.rounded(12, weight: .bold))
                    }
                    .foregroundStyle(Color.pocketvoiceRed)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 2)
            }
        }
        .frame(width: photoPreviewSize.width)
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
                .focused($isNameFocused)
                .submitLabel(.done)
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
        HStack(spacing: 10) {
            ForEach(PocketVoiceCategory.allCases) { item in
                Button {
                    category = item
                } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(category == item ? .white : Color.pocketvoiceInk.opacity(0.62))
                        .frame(width: 46, height: 46)
                        .background(category == item ? accent : Color.white.opacity(0.48), in: Circle())
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
                    size: 78,
                    action: togglePreview
                )
                .disabled(!hasPlayableVoice)
                .opacity(hasPlayableVoice ? 1 : 0.35)
            }

            TimelineView(.animation(paused: !isPreviewPlaying)) { context in
                VoiceWaveformView(
                    levels: waveformLevels,
                    highlightedCount: highlightedBarCount(at: context.date)
                )
            }
            .frame(height: 48)
            .padding(.horizontal, 4)
            .accessibilityHidden(true)

            // A quiet hint under the waveform, not a button-like pill.
            Text(status)
                .font(PocketVoiceFont.rounded(12, weight: .medium))
                .foregroundStyle(recorder.isRecording ? Color.pocketvoiceRedDeep : Color.pocketvoiceInk.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 10)
    }

    private var photoPreviewSize: CGSize {
        CGSize(width: 176, height: 176)
    }

    /// The new recording if there is one, otherwise the saved voice.
    private var waveformLevels: [Float] {
        recorder.isRecording || recorder.lastRecordedURL != nil ? recorder.levels : savedLevels
    }

    /// While previewing, only the bars already played are bright.
    private func highlightedBarCount(at date: Date) -> Int {
        guard isPreviewPlaying, let previewStartedAt, previewDuration > 0 else { return waveformLevels.count }
        let played = date.timeIntervalSince(previewStartedAt) / previewDuration
        return Int(played * Double(waveformLevels.count)) + 1
    }

    private var hasPlayableVoice: Bool {
        audioFileName != nil || recorder.lastRecordedURL != nil
    }

    private func toggleRecording() {
        if recorder.isRecording {
            recorder.stop()
            status = text(.recorded)
            return
        }

        stopPreview()
        PocketVoiceAudioPlayback.stop()
        let url = PocketVoiceStore.draftAudioURL(for: draftID)
        Task {
            do {
                try await recorder.start(url: url, maxDuration: PocketVoicePlus.recordingSeconds(isPlus: plus.isActive))
                status = text(.recording)
            } catch {
                status = error.localizedDescription
            }
        }
    }

    /// Closing the editor (saved or not) stops recording and preview, and
    /// drops an unsaved draft recording.
    private func cleanUpOnClose() {
        stopPreview()
        if recorder.isRecording {
            recorder.stop()
        }
        let id = draftID
        Task {
            await PocketVoiceAudioSession.waitForPendingWork()
            PocketVoiceStore.discardDraftAudio(for: id)
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
        let url: URL
        if let lastRecordedURL = recorder.lastRecordedURL,
           FileManager.default.fileExists(atPath: lastRecordedURL.path) {
            url = lastRecordedURL
        } else if let audioFileName {
            url = PocketVoiceStore.fileURL(audioFileName)
        } else {
            return
        }

        Task {
            do {
                let duration = try await VoiceRecorder.play(url: url)
                status = text(.preview)
                pulsePreview(duration: duration)
            } catch {
                status = error.localizedDescription
                stopPreview()
            }
        }
    }

    private func pulsePreview(duration: TimeInterval) {
        previewResetWorkItem?.cancel()
        previewStartedAt = Date()
        previewDuration = duration
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
            sourcePhotoData = image.pngData()
            photoDecoration = .empty
            cropImage = image
            isShowingPhotoCropper = true
        } catch {
            status = error.localizedDescription
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task { await saveAndClose() }
    }

    @MainActor
    private func saveAndClose() async {
        stopPreview()
        if recorder.isRecording {
            recorder.stop()
        }
        // Let the recorder finish writing before the draft file is moved.
        await PocketVoiceAudioSession.waitForPendingWork()

        do {
            var savedAudioFileName = audioFileName
            if let draftURL = recorder.lastRecordedURL,
               FileManager.default.fileExists(atPath: draftURL.path) {
                savedAudioFileName = try PocketVoiceStore.commitDraftAudio(for: draftID)
                // Keep it even if a later step fails and the user taps save again.
                audioFileName = savedAudioFileName
            }

            let normalizedPhotoData = photoData.flatMap { normalizedPhotoPNGData(from: $0) ?? $0 }
            let normalizedSourcePhotoData = sourcePhotoData.flatMap { normalizedPhotoPNGData(from: $0) ?? $0 }
            let savedPhotoFileName = try normalizedPhotoData.map { try PocketVoiceStore.savePhotoData($0, for: draftID) } ?? person?.photoFileName
            let savedSourcePhotoFileName = try normalizedSourcePhotoData.map { try PocketVoiceStore.saveSourcePhotoData($0, for: draftID) } ?? person?.sourcePhotoFileName
            let updated = PocketVoicePerson(
                id: draftID,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category,
                photoFileName: savedPhotoFileName,
                sourcePhotoFileName: savedSourcePhotoFileName,
                photoDecoration: photoDecoration,
                audioFileName: savedAudioFileName,
                createdAt: person?.createdAt ?? Date(),
                sortOrder: person?.sortOrder ?? 0,
                isPinned: person?.isPinned ?? false
            )

            try PocketVoiceStore.upsert(updated)
            onSave()
            dismiss()
        } catch {
            status = error.localizedDescription
            isSaving = false
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
    let initialDecoration: PocketVoicePhotoDecoration
    let onComplete: (Data, PocketVoicePhotoDecoration) -> Void
    let onCancel: () -> Void

    @State private var scale: CGFloat
    @State private var lastScale: CGFloat
    @State private var offset: CGSize
    @State private var lastOffset: CGSize
    @State private var placedStickerOffsets: [Int: CGSize]
    @State private var paletteDragOffsets: [Int: CGSize] = [:]
    @State private var stickerDragStarts: [Int: CGSize] = [:]

    private let frameSize: CGFloat = 300
    private let outputSize = CGSize(width: 1_000, height: 1_000)

    init(
        image: UIImage,
        title: String,
        accent: Color,
        initialDecoration: PocketVoicePhotoDecoration,
        onComplete: @escaping (Data, PocketVoicePhotoDecoration) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.image = image
        self.title = title
        self.accent = accent
        self.initialDecoration = initialDecoration
        self.onComplete = onComplete
        self.onCancel = onCancel

        let initialScale = min(max(CGFloat(initialDecoration.scale), 1), 3)
        let initialOffset = CGSize(width: initialDecoration.offsetWidth, height: initialDecoration.offsetHeight)
        let stickers = Dictionary(uniqueKeysWithValues: initialDecoration.stickers.map {
            ($0.id, CGSize(width: $0.offsetWidth, height: $0.offsetHeight))
        })
        _scale = State(initialValue: initialScale)
        _lastScale = State(initialValue: initialScale)
        _offset = State(initialValue: initialOffset)
        _lastOffset = State(initialValue: initialOffset)
        _placedStickerOffsets = State(initialValue: stickers)
    }

    private var stickers: [DecorationSticker] {
        [
            DecorationSticker(id: 0, emoji: "✨", size: 50, rotation: -18, base: CGSize(width: -142, height: -236)),
            DecorationSticker(id: 1, emoji: "🌸", size: 63, rotation: 14, base: CGSize(width: -52, height: -258)),
            DecorationSticker(id: 2, emoji: "💛", size: 54, rotation: -8, base: CGSize(width: 78, height: -240)),
            DecorationSticker(id: 3, emoji: "⭐️", size: 45, rotation: 22, base: CGSize(width: 154, height: -188)),
            DecorationSticker(id: 4, emoji: "🥰", size: 66, rotation: -12, base: CGSize(width: -144, height: 226)),
            DecorationSticker(id: 5, emoji: "🎈", size: 57, rotation: 20, base: CGSize(width: -58, height: 262)),
            DecorationSticker(id: 6, emoji: "🌈", size: 69, rotation: -6, base: CGSize(width: 58, height: 232)),
            DecorationSticker(id: 7, emoji: "🍀", size: 51, rotation: 15, base: CGSize(width: 144, height: 260)),
            DecorationSticker(id: 8, emoji: "💬", size: 60, rotation: -15, base: CGSize(width: 160, height: -254)),
            DecorationSticker(id: 9, emoji: "🎵", size: 48, rotation: 18, base: CGSize(width: -166, height: -160)),
            DecorationSticker(id: 10, emoji: "❤️", size: 58, rotation: 10, base: CGSize(width: -184, height: -66)),
            DecorationSticker(id: 11, emoji: "😊", size: 62, rotation: -10, base: CGSize(width: 184, height: -76)),
            DecorationSticker(id: 12, emoji: "🌷", size: 56, rotation: 18, base: CGSize(width: -184, height: 72)),
            DecorationSticker(id: 13, emoji: "☀️", size: 61, rotation: -16, base: CGSize(width: 184, height: 70)),
            DecorationSticker(id: 14, emoji: "🫶", size: 64, rotation: 8, base: CGSize(width: -116, height: -300)),
            DecorationSticker(id: 15, emoji: "🎀", size: 55, rotation: -20, base: CGSize(width: 124, height: -304)),
            DecorationSticker(id: 16, emoji: "🍓", size: 57, rotation: 14, base: CGSize(width: -122, height: 308)),
            DecorationSticker(id: 17, emoji: "🌼", size: 60, rotation: -12, base: CGSize(width: 128, height: 306)),
            DecorationSticker(id: 18, emoji: "💫", size: 53, rotation: 24, base: CGSize(width: -4, height: -318)),
            DecorationSticker(id: 19, emoji: "🎧", size: 58, rotation: -8, base: CGSize(width: 2, height: 318))
        ]
    }

    private var availableStickers: [DecorationSticker] {
        stickers.filter { placedStickerOffsets[$0.id] == nil }
    }

    var body: some View {
        ZStack {
            AppBackgroundImage()

            VStack(spacing: 20) {
                header

                Spacer(minLength: 4)

                ZStack {
                    RoundedRectangle(cornerRadius: 30)
                        .fill(Color.white.opacity(0.38))
                        .frame(width: frameSize + 18, height: frameSize + 18)
                        .zIndex(0)

                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: frameSize, height: frameSize)
                            .scaleEffect(scale)
                            .offset(offset)
                    }
                    .frame(width: frameSize, height: frameSize)
                    .contentShape(RoundedRectangle(cornerRadius: 26))
                    .clipShape(RoundedRectangle(cornerRadius: 26))
                    .gesture(dragGesture.simultaneously(with: magnificationGesture))
                    .overlay {
                        RoundedRectangle(cornerRadius: 26)
                            .stroke(.white.opacity(0.92), lineWidth: 3)
                    }
                    .zIndex(1)

                    ForEach(placedStickersForDisplay()) { sticker in
                        placedStickerView(sticker)
                    }
                    .zIndex(2)

                    ForEach(availableStickers) { sticker in
                        paletteStickerView(sticker)
                    }
                    .zIndex(3)
                }
                .frame(width: 390, height: 540)
                .shadow(color: Color(hex: 0x3A2500).opacity(0.16), radius: 24, y: 12)

                Spacer(minLength: 8)
            }
        }
        .onAppear(perform: clampOffset)
    }

    private var header: some View {
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
                if let data = decoratedPNGData() {
                    onComplete(data, decorationFromState())
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
    }

    private func paletteStickerView(_ sticker: DecorationSticker) -> some View {
        let current = paletteStickerCurrentOffset(sticker)
        return Text(sticker.emoji)
            .font(.system(size: sticker.size))
            .rotationEffect(.degrees(sticker.rotation))
            .shadow(color: .black.opacity(0.16), radius: 5, y: 3)
            .frame(width: 64, height: 64)
            .contentShape(Rectangle())
            .offset(current)
            // One gesture handles both: a drag drops the sticker where it is
            // released, and a tap (barely any movement) places it on the photo.
            // A separate tap gesture never fired because this drag took the touch first.
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        paletteDragOffsets[sticker.id] = value.translation
                    }
                    .onEnded { value in
                        let moved = hypot(value.translation.width, value.translation.height)
                        if moved < 8 {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                placedStickerOffsets[sticker.id] = tapPlacement(for: sticker)
                            }
                        } else {
                            let final = CGSize(width: sticker.base.width + value.translation.width, height: sticker.base.height + value.translation.height)
                            if isInsideFrame(final) {
                                placedStickerOffsets[sticker.id] = final
                            }
                        }
                        paletteDragOffsets[sticker.id] = nil
                    }
            )
    }

    /// Where a tapped sticker lands: inside the photo, toward the side the
    /// sticker sits on in the palette, so it decorates the edge instead of
    /// covering the face in the middle.
    private func tapPlacement(for sticker: DecorationSticker) -> CGSize {
        let reach = frameSize / 2 * 0.68
        let largest = max(abs(sticker.base.width), abs(sticker.base.height), 1)
        return CGSize(
            width: sticker.base.width / largest * reach,
            height: sticker.base.height / largest * reach
        )
    }

    private func placedStickerView(_ sticker: DecorationSticker) -> some View {
        let current = placedStickerOffsets[sticker.id] ?? .zero
        return Text(sticker.emoji)
            .font(.system(size: sticker.size))
            .rotationEffect(.degrees(sticker.rotation))
            .shadow(color: .black.opacity(0.18), radius: 5, y: 3)
            .frame(width: 72, height: 72)
            .contentShape(Rectangle())
            .offset(current)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let start = stickerDragStarts[sticker.id] ?? current
                        stickerDragStarts[sticker.id] = start
                        placedStickerOffsets[sticker.id] = CGSize(
                            width: start.width + value.translation.width,
                            height: start.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        if let final = placedStickerOffsets[sticker.id], !isInsideFrame(final) {
                            placedStickerOffsets[sticker.id] = nil
                        }
                        stickerDragStarts[sticker.id] = nil
                    }
            )
    }

    private func paletteStickerCurrentOffset(_ sticker: DecorationSticker) -> CGSize {
        let adjustment = paletteDragOffsets[sticker.id] ?? .zero
        return CGSize(width: sticker.base.width + adjustment.width, height: sticker.base.height + adjustment.height)
    }

    private func placedStickersForDisplay() -> [DecorationSticker] {
        stickers.filter { placedStickerOffsets[$0.id] != nil }
    }

    private func placedStickersForOutput() -> [(DecorationSticker, CGSize)] {
        placedStickersForDisplay().compactMap { sticker in
            guard let current = placedStickerOffsets[sticker.id], isInsideFrame(current) else { return nil }
            return (sticker, current)
        }
    }

    private func isInsideFrame(_ position: CGSize) -> Bool {
        abs(position.width) <= frameSize / 2 && abs(position.height) <= frameSize / 2
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

    private func decoratedPNGData() -> Data? {
        guard let cropped = croppedImage() else { return image.pngData() }
        let renderer = UIGraphicsImageRenderer(size: outputSize)
        return renderer.pngData { _ in
            cropped.draw(in: CGRect(origin: .zero, size: outputSize))

            let ratio = outputSize.width / frameSize
            for (sticker, stickerOffset) in placedStickersForOutput() {
                let fontSize = sticker.size * ratio
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: fontSize)
                ]
                let attributed = NSAttributedString(string: sticker.emoji, attributes: attributes)
                let textSize = attributed.size()
                let center = CGPoint(
                    x: outputSize.width / 2 + stickerOffset.width * ratio,
                    y: outputSize.height / 2 + stickerOffset.height * ratio
                )
                let context = UIGraphicsGetCurrentContext()
                context?.saveGState()
                context?.translateBy(x: center.x, y: center.y)
                context?.rotate(by: CGFloat(sticker.rotation * .pi / 180))
                attributed.draw(in: CGRect(x: -textSize.width / 2, y: -textSize.height / 2, width: textSize.width, height: textSize.height))
                context?.restoreGState()
            }
        }
    }

    private func croppedImage() -> UIImage? {
        guard let cgImage = image.cgImage else { return image }
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
              let cropped = cgImage.cropping(to: cropRect) else { return image }
        let renderer = UIGraphicsImageRenderer(size: outputSize)
        return renderer.image { _ in
            UIImage(cgImage: cropped).draw(in: CGRect(origin: .zero, size: outputSize))
        }
    }

    private func decorationFromState() -> PocketVoicePhotoDecoration {
        PocketVoicePhotoDecoration(
            scale: Double(scale),
            offsetWidth: Double(offset.width),
            offsetHeight: Double(offset.height),
            stickers: placedStickersForOutput().map { sticker, stickerOffset in
                PocketVoicePhotoSticker(
                    id: sticker.id,
                    emoji: sticker.emoji,
                    size: Double(sticker.size),
                    rotation: sticker.rotation,
                    offsetWidth: Double(stickerOffset.width),
                    offsetHeight: Double(stickerOffset.height)
                )
            }
        )
    }
}
private struct DecorationSticker: Identifiable {
    let id: Int
    let emoji: String
    let size: CGFloat
    let rotation: Double
    let base: CGSize
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
    /// Loudness per waveform bar (0...1) of the current recording, filled in live.
    @Published var levels: [Float] = []

    var lastRecordedURL: URL?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var maxDuration = 10.0
    private static var player: AVAudioPlayer?

    @MainActor
    func start(url: URL, maxDuration: TimeInterval) async throws {
        try PocketVoiceStore.ensureContainerExists()

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        recorder = try await PocketVoiceAudioSession.startRecorder(
            url: url,
            settings: settings,
            duration: maxDuration,
            delegate: self
        )
        self.maxDuration = maxDuration
        elapsed = 0
        levels = []
        isRecording = true
        lastRecordedURL = url

        timer?.invalidate()
        // Sample the mic level often and keep the loudest value per bar.
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let recorder else { return }
            elapsed = min(recorder.currentTime, self.maxDuration)
            recorder.updateMeters()
            let level = VoiceWaveform.level(fromDecibels: recorder.averagePower(forChannel: 0))
            let barDuration = self.maxDuration / Double(VoiceWaveform.barCount)
            let index = min(Int(elapsed / barDuration), VoiceWaveform.barCount - 1)
            while levels.count <= index {
                levels.append(0)
            }
            levels[index] = max(levels[index], level)
            if elapsed >= self.maxDuration {
                stop()
            }
        }
    }

    func stop() {
        PocketVoiceAudioSession.stopRecorder(recorder)
        recorder = nil
        timer?.invalidate()
        timer = nil
        elapsed = maxDuration
        isRecording = false
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // May arrive off the main thread; UI state lives on main.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isRecording = false
            elapsed = maxDuration
            timer?.invalidate()
            timer = nil
            if self.recorder === recorder {
                self.recorder = nil
            }
            PocketVoiceAudioSession.deactivate()
        }
    }

    @MainActor
    static func play(url: URL) async throws -> TimeInterval {
        PocketVoiceAudioSession.stopPlayer(player, deactivate: false)
        player = nil
        let newPlayer = try await PocketVoiceAudioSession.startPlayer(url: url, delegate: nil)
        player = newPlayer
        return newPlayer.duration
    }

    static func stopPlayback() {
        PocketVoiceAudioSession.stopPlayer(player, deactivate: player != nil)
        player = nil
    }

    static func applyVolume() {
        player?.volume = PocketVoiceShared.playbackVolume
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

/// 40 bars. While recording, the bars span the maximum length (10 s or 1 min);
/// a finished recording is spread across all 40 bars.
private enum VoiceWaveform {
    static let barCount = 40

    /// Maps dBFS (about -45 quiet ... -5 loud) to 0...1. Squaring spreads out
    /// normal speech levels so louder and softer syllables look different.
    static func level(fromDecibels decibels: Float) -> Float {
        let linear = min(max((decibels + 45) / 40, 0), 1)
        return linear * linear
    }

    /// Reads a recording and returns one loudness value per bar.
    static func levels(for url: URL) async -> [Float] {
        await Task.detached(priority: .utility) {
            guard let file = try? AVAudioFile(forReading: url),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: buffer)) != nil,
                  let samples = buffer.floatChannelData?[0] else {
                return []
            }

            let frameCount = Int(buffer.frameLength)
            let framesPerBar = max(Int((Double(frameCount) / Double(barCount)).rounded(.up)), 1)
            var result: [Float] = []
            var start = 0
            while start < frameCount, result.count < barCount {
                let end = min(start + framesPerBar, frameCount)
                var sum: Float = 0
                for index in start..<end {
                    sum += samples[index] * samples[index]
                }
                let rms = (sum / Float(end - start)).squareRoot()
                result.append(level(fromDecibels: 20 * log10(max(rms, 0.000_001))))
                start = end
            }
            return result
        }.value
    }
}

private struct VoiceWaveformView: View {
    let levels: [Float]
    let highlightedCount: Int

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 3
            let count = VoiceWaveform.barCount
            let barWidth = max((proxy.size.width - spacing * CGFloat(count - 1)) / CGFloat(count), 1)

            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<count, id: \.self) { index in
                    let hasSound = index < levels.count
                    let level = hasSound ? CGFloat(levels[index]) : 0
                    Capsule()
                        .fill(Color.white.opacity(barOpacity(index: index, hasSound: hasSound)))
                        .frame(width: barWidth, height: max(proxy.size.height * level, 4))
                        .animation(.easeOut(duration: 0.12), value: level)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func barOpacity(index: Int, hasSound: Bool) -> Double {
        guard hasSound else { return 0.28 }
        return index < highlightedCount ? 1 : 0.5
    }
}
