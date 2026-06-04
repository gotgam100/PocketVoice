import AVFoundation
import Foundation

struct PocketVoicePerson: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var category: PocketVoiceCategory
    var accent: PocketVoiceAccent
    var photoFileName: String?
    var audioFileName: String?
    var createdAt: Date
    var sortOrder: Int

    init(
        id: String,
        name: String,
        category: PocketVoiceCategory = .family,
        accent: PocketVoiceAccent = .coral,
        photoFileName: String? = nil,
        audioFileName: String? = nil,
        createdAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.accent = accent
        self.photoFileName = photoFileName
        self.audioFileName = audioFileName
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case accent
        case photoFileName
        case audioFileName
        case createdAt
        case sortOrder
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
        accent = try container.decodeIfPresent(PocketVoiceAccent.self, forKey: .accent) ?? .coral
        photoFileName = try container.decodeIfPresent(String.self, forKey: .photoFileName)
        audioFileName = try container.decodeIfPresent(String.self, forKey: .audioFileName)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }

    var hasPhoto: Bool {
        photoFileName != nil
    }

    var hasAudio: Bool {
        guard let audioFileName else {
            return false
        }
        return FileManager.default.fileExists(atPath: PocketVoiceStore.fileURL(audioFileName).path)
    }
}

enum PocketVoiceCategory: String, Codable, CaseIterable, Identifiable {
    case family
    case friend
    case partner
    case coworker
    case pet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .family: "가족"
        case .friend: "친구"
        case .partner: "연인"
        case .coworker: "동료"
        case .pet: "반려"
        }
    }

    var symbol: String {
        switch self {
        case .family: "house.fill"
        case .friend: "face.smiling.fill"
        case .partner: "heart.fill"
        case .coworker: "briefcase.fill"
        case .pet: "pawprint.fill"
        }
    }

    var accent: PocketVoiceAccent {
        switch self {
        case .family: .sky
        case .friend: .mint
        case .partner: .coral
        case .coworker: .lavender
        case .pet: .peach
        }
    }
}

enum PocketVoiceAccent: String, Codable, CaseIterable, Identifiable {
    case coral
    case peach
    case mint
    case sky
    case lavender
    case lemon

    var id: String { rawValue }

    var hex: UInt32 {
        switch self {
        case .coral: 0x9F1239
        case .peach: 0x9A3412
        case .mint: 0x047857
        case .sky: 0x0754B8
        case .lavender: 0x4C1D95
        case .lemon: 0xA16207
        }
    }
}

enum PocketVoiceShared {
    static let appGroupID = "group.com.baekmac.pocketvoice"
    static let logKey = "pocketvoice.logs"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static var homeURL: URL {
        URL(string: "pocketvoice://home")!
    }

    static func autoplayURL(for personID: String?) -> URL {
        var components = URLComponents()
        components.scheme = "pocketvoice"
        components.host = "play"
        if let personID {
            components.queryItems = [URLQueryItem(name: "person", value: personID)]
        }
        return components.url ?? URL(string: "pocketvoice://play")!
    }

    static func appendLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)"
        let defaults = sharedDefaults ?? .standard
        var logs = defaults.stringArray(forKey: logKey) ?? []
        logs.insert(line, at: 0)
        defaults.set(Array(logs.prefix(30)), forKey: logKey)
    }

    static func recentLogs() -> [String] {
        (sharedDefaults ?? .standard).stringArray(forKey: logKey) ?? []
    }
}

enum PocketVoiceStore {
    static let maxPeople = 10
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
            guard people.count < maxPeople else {
                throw PocketVoiceError.peopleLimitReached
            }
            var newPerson = person
            newPerson.sortOrder = people.count
            people.append(newPerson)
        }
        try savePeople(people)
    }

    static func reorderPeople(from source: IndexSet, to destination: Int) throws {
        var people = loadPeople()
        let moving = source.map { people[$0] }
        people.removeAll { person in
            moving.contains { $0.id == person.id }
        }
        let adjustedDestination = min(destination, people.count)
        people.insert(contentsOf: moving, at: adjustedDestination)
        for index in people.indices {
            people[index].sortOrder = index
        }
        try savePeople(people)
    }

    static func delete(_ person: PocketVoicePerson) throws {
        var people = loadPeople()
        people.removeAll { $0.id == person.id }
        try savePeople(people)
        try removeFile(named: person.photoFileName)
        try removeFile(named: person.audioFileName)
    }

    static func person(id: String?) -> PocketVoicePerson? {
        let people = loadPeople()
        guard let id else {
            return people.first
        }
        return people.first { $0.id == id }
    }

    static func defaultPerson() -> PocketVoicePerson? {
        loadPeople().first
    }

    static func savePhotoData(_ data: Data, for personID: String) throws -> String {
        try ensureContainerExists()
        let fileName = "photo-\(personID).png"
        try data.write(to: fileURL(fileName), options: [.atomic])
        return fileName
    }

    static func audioFileName(for personID: String) -> String {
        "voice-\(personID).m4a"
    }

    static func audioURL(for personID: String) -> URL {
        fileURL(audioFileName(for: personID))
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
    case peopleLimitReached
    case personMissing
    case audioMissing

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            "App Group container is unavailable."
        case .peopleLimitReached:
            "최대 10명까지 등록할 수 있습니다."
        case .personMissing:
            "인물을 찾을 수 없습니다."
        case .audioMissing:
            "녹음된 목소리가 없습니다."
        }
    }
}

enum PocketVoiceAudioPlayback {
    private static var player: AVAudioPlayer?

    static func play(personID: String?) throws -> TimeInterval {
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

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try session.setActive(true)

        player = try AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        player?.play()
        return player?.duration ?? 0
    }

    static func stop() {
        player?.stop()
        player = nil
    }

    static var isPlaying: Bool {
        player?.isPlaying == true
    }
}
