import AVFoundation
import Foundation
import WidgetKit

struct PocketVoicePerson: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var category: PocketVoiceCategory
    var photoFileName: String?
    var sourcePhotoFileName: String?
    var photoDecoration: PocketVoicePhotoDecoration?
    var audioFileName: String?
    var createdAt: Date
    var sortOrder: Int
    /// "최애" pin: pinned people always stay at the top of the list.
    var isPinned: Bool

    init(
        id: String,
        name: String,
        category: PocketVoiceCategory = .family,
        photoFileName: String? = nil,
        sourcePhotoFileName: String? = nil,
        photoDecoration: PocketVoicePhotoDecoration? = nil,
        audioFileName: String? = nil,
        createdAt: Date = Date(),
        sortOrder: Int = 0,
        isPinned: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.photoFileName = photoFileName
        self.sourcePhotoFileName = sourcePhotoFileName
        self.photoDecoration = photoDecoration
        self.audioFileName = audioFileName
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.isPinned = isPinned
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case photoFileName
        case sourcePhotoFileName
        case photoDecoration
        case audioFileName
        case createdAt
        case sortOrder
        case isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        if let rawCategory = try container.decodeIfPresent(String.self, forKey: .category) {
            category = PocketVoiceCategory(rawValue: rawCategory) ?? .family
        } else {
            category = .family
        }
        photoFileName = try container.decodeIfPresent(String.self, forKey: .photoFileName)
        sourcePhotoFileName = try container.decodeIfPresent(String.self, forKey: .sourcePhotoFileName)
        photoDecoration = try container.decodeIfPresent(PocketVoicePhotoDecoration.self, forKey: .photoDecoration)
        audioFileName = try container.decodeIfPresent(String.self, forKey: .audioFileName)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    var hasAudio: Bool {
        guard let audioFileName else {
            return false
        }
        return FileManager.default.fileExists(atPath: PocketVoiceStore.fileURL(audioFileName).path)
    }
}

struct PocketVoicePhotoDecoration: Codable, Equatable {
    var scale: Double
    var offsetWidth: Double
    var offsetHeight: Double
    var stickers: [PocketVoicePhotoSticker]

    static let empty = PocketVoicePhotoDecoration(scale: 1, offsetWidth: 0, offsetHeight: 0, stickers: [])
}

struct PocketVoicePhotoSticker: Codable, Equatable, Identifiable {
    var id: Int
    var emoji: String
    var size: Double
    var rotation: Double
    var offsetWidth: Double
    var offsetHeight: Double
}

enum PocketVoiceCategory: String, Codable, CaseIterable, Identifiable {
    case family
    case friend
    case partner
    case pet
    case favorite

    var id: String { rawValue }

    var title: String {
        let english = PocketVoiceShared.isEnglish
        return switch self {
        case .family: english ? "Family" : "가족"
        case .friend: english ? "Friend" : "친구"
        case .partner: english ? "Partner" : "연인"
        case .pet: english ? "Pet" : "반려"
        case .favorite: english ? "Favorite" : "최애"
        }
    }

    var symbol: String {
        switch self {
        case .family: "house.fill"
        case .friend: "face.smiling.fill"
        case .partner: "heart.fill"
        case .pet: "pawprint.fill"
        case .favorite: "star.fill"
        }
    }

    var accent: PocketVoiceAccent {
        switch self {
        case .family: .sky
        case .friend: .mint
        case .partner: .coral
        case .pet: .peach
        case .favorite: .lemon
        }
    }
}

enum PocketVoiceAccent: String, Codable, CaseIterable, Identifiable {
    case coral
    case peach
    case mint
    case sky
    case lemon

    var id: String { rawValue }

    var hex: UInt32 {
        switch self {
        case .coral: 0x9F1239
        case .peach: 0x9A3412
        case .mint: 0x047857
        case .sky: 0x0754B8
        case .lemon: 0xA16207
        }
    }
}

enum PocketVoiceShared {
    static let appGroupID = "group.com.baekmac.pocketvoice"
    static let languageKey = "pocketvoice.language"
    static let logKey = "pocketvoice.logs"
    static let volumeKey = "pocketvoice.volume"
    private static let playingPersonKey = "pocketvoice.playingPersonID"
    private static let playingUntilKey = "pocketvoice.playingUntil"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static var languageRawValue: String {
        (sharedDefaults ?? .standard).string(forKey: languageKey) ?? "ko"
    }

    static var isEnglish: Bool {
        languageRawValue == "en"
    }

    static func setLanguage(_ rawValue: String) {
        UserDefaults.standard.set(rawValue, forKey: languageKey)
        sharedDefaults?.set(rawValue, forKey: languageKey)
    }

    /// App volume (0...1), relative to the device volume. Kept in the shared
    /// App Group defaults so in-app playback and widget playback both use it.
    static var playbackVolume: Float {
        let defaults = sharedDefaults ?? .standard
        guard defaults.object(forKey: volumeKey) != nil else { return 1 }
        return Float(min(max(defaults.double(forKey: volumeKey), 0), 1))
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// The person whose voice is playing right now, and when it ends.
    /// Written by the app, read by the widget to show a stop button.
    static var nowPlaying: (personID: String, until: Date)? {
        let defaults = sharedDefaults ?? .standard
        guard let personID = defaults.string(forKey: playingPersonKey),
              let until = defaults.object(forKey: playingUntilKey) as? Date,
              until > Date() else {
            return nil
        }
        return (personID, until)
    }

    /// `reloadWidgets` is false when the widget itself started the change:
    /// WidgetKit already reloads a widget after its button's intent finishes,
    /// and extra reloads can leave the widget briefly unresponsive to taps.
    static func setNowPlaying(personID: String?, duration: TimeInterval = 0, reloadWidgets: Bool = true) {
        let defaults = sharedDefaults ?? .standard
        if let personID {
            defaults.set(personID, forKey: playingPersonKey)
            defaults.set(Date().addingTimeInterval(duration + 0.3), forKey: playingUntilKey)
        } else {
            defaults.removeObject(forKey: playingPersonKey)
            defaults.removeObject(forKey: playingUntilKey)
        }
        if reloadWidgets {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    static var isRunningInExtension: Bool {
        Bundle.main.bundlePath.hasSuffix(".appex")
    }

    static func appendLog(_ message: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(message)"
        let defaults = sharedDefaults ?? .standard
        var logs = defaults.stringArray(forKey: logKey) ?? []
        logs.insert(line, at: 0)
        defaults.set(Array(logs.prefix(30)), forKey: logKey)
    }
}

enum PocketVoiceStore {
    private static let peopleFileName = "people.json"

    static var peopleFileURL: URL {
        fileURL(peopleFileName)
    }

    static func fileURL(_ fileName: String) -> URL {
        guard let container = PocketVoiceShared.containerURL else {
            return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        }
        return container.appendingPathComponent(fileName)
    }

    static func loadPeople() -> [PocketVoicePerson] {
        guard FileManager.default.fileExists(atPath: peopleFileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: peopleFileURL)
            return try JSONDecoder().decode([PocketVoicePerson].self, from: data)
                .enumerated()
                .map { index, person in
                    var updated = person
                    if updated.sortOrder == 0 {
                        updated.sortOrder = index
                    }
                    return updated
                }
                .sorted {
                    if $0.isPinned != $1.isPinned {
                        return $0.isPinned
                    }
                    if $0.sortOrder == $1.sortOrder {
                        return $0.createdAt < $1.createdAt
                    }
                    return $0.sortOrder < $1.sortOrder
                }
        } catch {
            PocketVoiceShared.appendLog("Failed to load people: \(error.localizedDescription)")
            return []
        }
    }

    static func savePeople(_ people: [PocketVoicePerson]) throws {
        try ensureContainerExists()
        let data = try JSONEncoder().encode(people)
        try data.write(to: peopleFileURL, options: [.atomic])
    }

    static func upsert(_ person: PocketVoicePerson) throws {
        var people = loadPeople()
        if let index = people.firstIndex(where: { $0.id == person.id }) {
            people[index] = person
        } else {
            // The free-version limit is enforced by the app UI (PocketVoicePlus),
            // so people restored from a backup are never refused here.
            var newPerson = person
            newPerson.sortOrder = people.count
            people.append(newPerson)
        }
        try savePeople(people)
    }

    static func delete(_ person: PocketVoicePerson) throws {
        var people = loadPeople()
        people.removeAll { $0.id == person.id }
        try savePeople(people)
        try removeFile(named: person.photoFileName)
        try removeFile(named: person.sourcePhotoFileName)
        try removeFile(named: person.audioFileName)
    }

    static func person(id: String?) -> PocketVoicePerson? {
        let people = loadPeople()
        guard let id else {
            return people.first(where: \.hasAudio) ?? people.first
        }
        return people.first { $0.id == id }
    }

    static func savePhotoData(_ data: Data, for personID: String) throws -> String {
        try saveImageData(data, fileName: "photo-\(personID).png")
    }

    static func saveSourcePhotoData(_ data: Data, for personID: String) throws -> String {
        try saveImageData(data, fileName: "photo-source-\(personID).png")
    }

    private static func saveImageData(_ data: Data, fileName: String) throws -> String {
        try ensureContainerExists()
        try data.write(to: fileURL(fileName), options: [.atomic])
        return fileName
    }

    static func audioFileName(for personID: String) -> String {
        "voice-\(personID).m4a"
    }

    static func audioURL(for personID: String) -> URL {
        fileURL(audioFileName(for: personID))
    }

    /// New recordings go here first, so closing the editor without saving
    /// never overwrites the voice that is already saved.
    static func draftAudioURL(for personID: String) -> URL {
        fileURL("voice-\(personID)-draft.m4a")
    }

    /// Replaces the saved voice with the draft recording and returns its file name.
    static func commitDraftAudio(for personID: String) throws -> String {
        let draft = draftAudioURL(for: personID)
        let final = audioURL(for: personID)
        if FileManager.default.fileExists(atPath: final.path) {
            try FileManager.default.removeItem(at: final)
        }
        try FileManager.default.moveItem(at: draft, to: final)
        return audioFileName(for: personID)
    }

    static func discardDraftAudio(for personID: String) {
        try? FileManager.default.removeItem(at: draftAudioURL(for: personID))
    }

    static func sourcePhotoData(for person: PocketVoicePerson) -> Data? {
        guard let sourcePhotoFileName = person.sourcePhotoFileName else { return nil }
        return try? Data(contentsOf: fileURL(sourcePhotoFileName))
    }

    static func photoData(for person: PocketVoicePerson) -> Data? {
        guard let photoFileName = person.photoFileName else {
            return nil
        }
        if let data = try? Data(contentsOf: fileURL(photoFileName)) {
            return data
        }

        if photoFileName.hasSuffix(".jpg") {
            let legacyName = photoFileName.replacingOccurrences(of: ".jpg", with: ".img")
            return try? Data(contentsOf: fileURL(legacyName))
        }

        if photoFileName.hasSuffix(".img") {
            let jpgName = photoFileName.replacingOccurrences(of: ".img", with: ".jpg")
            return try? Data(contentsOf: fileURL(jpgName))
        }

        return nil
    }

    static func ensureContainerExists() throws {
        guard let container = PocketVoiceShared.containerURL else {
            throw PocketVoiceError.appGroupUnavailable
        }
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    }

    private static func removeFile(named fileName: String?) throws {
        guard let fileName else {
            return
        }
        let url = fileURL(fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

enum PocketVoiceError: Error, LocalizedError {
    case appGroupUnavailable
    case personMissing
    case audioMissing
    case playbackFailed

    var errorDescription: String? {
        let english = PocketVoiceShared.isEnglish
        return switch self {
        case .appGroupUnavailable:
            english ? "Storage is unavailable." : "저장 공간을 사용할 수 없습니다."
        case .personMissing:
            english ? "Person not found." : "인물을 찾을 수 없습니다."
        case .audioMissing:
            english ? "No voice has been recorded." : "녹음된 목소리가 없습니다."
        case .playbackFailed:
            english ? "Couldn't play the voice." : "목소리를 재생하지 못했습니다."
        }
    }
}

/// Runs every AVAudioSession change on one serial background queue.
/// Activating or deactivating a session can block for a noticeable time, and
/// AVAudioPlayer/AVAudioRecorder prepare, start and stop calls touch the session
/// too, so all of them happen here; the main thread only waits asynchronously.
enum PocketVoiceAudioSession {
    private static let queue = DispatchQueue(label: "com.baekmac.pocketvoice.audio-session", qos: .userInitiated)

    /// Activates playback and starts a player for `url`.
    static func startPlayer(url: URL, delegate: AVAudioPlayerDelegate?) async throws -> AVAudioPlayer {
        try await run {
            let session = AVAudioSession.sharedInstance()
            // Non-mixable on purpose: iOS refuses to start a mixable (duckOthers)
            // session from the background ("Session activation failed"), which
            // broke widget taps after the app had been idle. Other audio pauses
            // and resumes when we deactivate with notifyOthersOnDeactivation.
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = delegate
            player.volume = PocketVoiceShared.playbackVolume
            player.prepareToPlay()
            guard player.play() else {
                throw PocketVoiceError.playbackFailed
            }
            return player
        }
    }

    static func stopPlayer(_ player: AVAudioPlayer?, deactivate: Bool) {
        queue.async {
            player?.stop()
            if deactivate {
                deactivateNow()
            }
        }
    }

    /// Activates recording and starts recording to `url` for at most `duration` seconds.
    static func startRecorder(
        url: URL,
        settings: [String: Any],
        duration: TimeInterval,
        delegate: AVAudioRecorderDelegate?
    ) async throws -> AVAudioRecorder {
        try await run {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
            try session.setCategory(.record, mode: .default, options: [])
            try session.setPreferredSampleRate(48_000)
            try session.setPreferredIOBufferDuration(0.02)
            try session.setActive(true)

            if let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try? session.setPreferredInput(builtInMic)
            }

            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = delegate
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()
            recorder.record(forDuration: duration)
            return recorder
        }
    }

    static func stopRecorder(_ recorder: AVAudioRecorder?) {
        queue.async {
            recorder?.stop()
            deactivateNow()
        }
    }

    /// Waits until every queued start/stop has finished, e.g. so a stopped
    /// recording is fully written to disk before the file is moved.
    static func waitForPendingWork() async {
        _ = try? await run {}
    }

    /// Lets music that was ducked or paused return to normal.
    static func deactivate() {
        queue.async {
            deactivateNow()
        }
    }

    private static func deactivateNow() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private static func run<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            queue.async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

@MainActor
enum PocketVoiceAudioPlayback {
    private static var player: AVAudioPlayer?
    private static let finishHandler = PlaybackFinishHandler()
    private(set) static var currentPersonID: String?

    @discardableResult
    static func play(personID: String?, reloadWidgets: Bool = true) async throws -> TimeInterval {
        guard let person = PocketVoiceStore.person(id: personID) else {
            throw PocketVoiceError.personMissing
        }

        guard let audioFileName = person.audioFileName else {
            throw PocketVoiceError.audioMissing
        }

        let url = PocketVoiceStore.fileURL(audioFileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PocketVoiceError.audioMissing
        }

        PocketVoiceAudioSession.stopPlayer(player, deactivate: false)
        player = nil

        let newPlayer = try await PocketVoiceAudioSession.startPlayer(url: url, delegate: finishHandler)
        player = newPlayer
        currentPersonID = person.id
        PocketVoiceShared.setNowPlaying(personID: person.id, duration: newPlayer.duration, reloadWidgets: reloadWidgets)
        return newPlayer.duration
    }

    /// Stops playback if this person's voice is already playing, otherwise plays it.
    /// Returns the playback duration, or 0 when it stopped.
    @discardableResult
    static func toggle(personID: String?, reloadWidgets: Bool = true) async throws -> TimeInterval {
        let resolvedID = PocketVoiceStore.person(id: personID)?.id
        if isPlaying, resolvedID != nil, resolvedID == currentPersonID {
            stop(reloadWidgets: reloadWidgets)
            return 0
        }
        return try await play(personID: personID, reloadWidgets: reloadWidgets)
    }

    static func stop(reloadWidgets: Bool = true) {
        let wasPlaying = player != nil
        PocketVoiceAudioSession.stopPlayer(player, deactivate: wasPlaying)
        player = nil
        currentPersonID = nil
        if wasPlaying {
            PocketVoiceShared.setNowPlaying(personID: nil, reloadWidgets: reloadWidgets)
        }
    }

    static var isPlaying: Bool {
        player?.isPlaying == true
    }

    /// Applies a changed app volume to the voice that is playing right now.
    static func applyVolume() {
        player?.volume = PocketVoiceShared.playbackVolume
    }

    fileprivate static func didFinish(_ finished: AVAudioPlayer) {
        guard finished === player else { return }
        player = nil
        currentPersonID = nil
        PocketVoiceAudioSession.deactivate()
        // No reload: the widget timeline already switches back to ▶ when the clip ends.
        PocketVoiceShared.setNowPlaying(personID: nil, reloadWidgets: false)
    }
}

private final class PlaybackFinishHandler: NSObject, AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            PocketVoiceAudioPlayback.didFinish(player)
        }
    }
}
