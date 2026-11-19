import AppIntents
import Foundation

// Shared by the app and the widget extension.
// PlayPersonVoiceIntent must be compiled into the app target too: as an
// AudioPlaybackIntent, iOS runs it in the app's process (in the background),
// which is the only place a widget tap is allowed to play sound.

struct PocketVoicePersonEntity: AppEntity, Identifiable, Hashable {
    static let emptyID = "__pocketvoice_empty_slot__"
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Person")
    static var defaultQuery = PocketVoicePersonQuery()

    let id: String

    @Property(title: "Name")
    var name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(person: PocketVoicePerson) {
        self.init(id: person.id, name: person.name)
    }

    var displayRepresentation: DisplayRepresentation {
        if id == Self.emptyID {
            return DisplayRepresentation(
                title: "Leave empty",
                subtitle: "None"
            )
        }

        return DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }

    /// The stored person ID, or nil for the "leave empty" slot.
    var personID: String? {
        id == Self.emptyID ? nil : id
    }

    static func == (lhs: PocketVoicePersonEntity, rhs: PocketVoicePersonEntity) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension PocketVoicePersonEntity {
    static var emptySlot: PocketVoicePersonEntity {
        PocketVoicePersonEntity(id: emptyID, name: PocketVoiceShared.isEnglish ? "Leave empty" : "비워두기")
    }
}

struct PocketVoicePersonQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [PocketVoicePersonEntity] {
        var entities = PocketVoiceStore.loadPeople()
            .filter { identifiers.contains($0.id) }
            .map(PocketVoicePersonEntity.init(person:))

        if identifiers.contains(PocketVoicePersonEntity.emptyID) {
            entities.insert(PocketVoicePersonEntity.emptySlot, at: 0)
        }

        return entities
    }

    func entities(matching string: String) async throws -> [PocketVoicePersonEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let people = PocketVoiceStore.loadPeople()
            .filter { person in
                query.isEmpty || person.name.lowercased().contains(query)
            }
            .map(PocketVoicePersonEntity.init(person:))

        if query.isEmpty || "비워두기".contains(query) || "선택 안 함".contains(query) || "leave empty".contains(query) || "none".contains(query) {
            return [PocketVoicePersonEntity.emptySlot] + people
        }

        return people
    }

    func suggestedEntities() async throws -> [PocketVoicePersonEntity] {
        [PocketVoicePersonEntity.emptySlot] + PocketVoiceStore.loadPeople()
            .map(PocketVoicePersonEntity.init(person:))
    }

    func defaultResult() async -> PocketVoicePersonEntity? {
        nil
    }
}

// One options provider per widget slot. Their defaultResult() pre-fills a newly
// added widget with the app's people in saved order, so Edit Widget shows who is
// actually on the widget instead of four empty rows.
private enum PocketVoiceSlotOptions {
    static func choices() -> [PocketVoicePersonEntity] {
        [PocketVoicePersonEntity.emptySlot] + PocketVoiceStore.loadPeople().map(PocketVoicePersonEntity.init(person:))
    }

    static func person(at index: Int) -> PocketVoicePersonEntity? {
        let people = PocketVoiceStore.loadPeople()
        guard people.indices.contains(index) else { return nil }
        return PocketVoicePersonEntity(person: people[index])
    }
}

struct PocketVoiceFirstSlotOptions: DynamicOptionsProvider {
    func results() async throws -> [PocketVoicePersonEntity] { PocketVoiceSlotOptions.choices() }
    func defaultResult() async -> PocketVoicePersonEntity? { PocketVoiceSlotOptions.person(at: 0) }
}

struct PocketVoiceSecondSlotOptions: DynamicOptionsProvider {
    func results() async throws -> [PocketVoicePersonEntity] { PocketVoiceSlotOptions.choices() }
    func defaultResult() async -> PocketVoicePersonEntity? { PocketVoiceSlotOptions.person(at: 1) }
}

struct PocketVoiceThirdSlotOptions: DynamicOptionsProvider {
    func results() async throws -> [PocketVoicePersonEntity] { PocketVoiceSlotOptions.choices() }
    func defaultResult() async -> PocketVoicePersonEntity? { PocketVoiceSlotOptions.person(at: 2) }
}

struct PocketVoiceFourthSlotOptions: DynamicOptionsProvider {
    func results() async throws -> [PocketVoicePersonEntity] { PocketVoiceSlotOptions.choices() }
    func defaultResult() async -> PocketVoicePersonEntity? { PocketVoiceSlotOptions.person(at: 3) }
}

struct PocketVoiceWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Pocket Voice widget settings"
    static var description = IntentDescription("Select people to add to the widget.")

    @Parameter(title: "First", optionsProvider: PocketVoiceFirstSlotOptions())
    var firstPerson: PocketVoicePersonEntity?

    @Parameter(title: "Second", optionsProvider: PocketVoiceSecondSlotOptions())
    var secondPerson: PocketVoicePersonEntity?

    @Parameter(title: "Third", optionsProvider: PocketVoiceThirdSlotOptions())
    var thirdPerson: PocketVoicePersonEntity?

    @Parameter(title: "Fourth", optionsProvider: PocketVoiceFourthSlotOptions())
    var fourthPerson: PocketVoicePersonEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Order \(\.$firstPerson), \(\.$secondPerson), \(\.$thirdPerson), \(\.$fourthPerson)")
    }
}

/// Plays (or stops) a saved voice without bringing the app to the foreground.
/// Used by the home screen widget's play button.
struct PlayPersonVoiceIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play Voice"
    static var description = IntentDescription("Plays a saved voice without opening the app.")
    // Widget-only for now: keep it out of the Shortcuts app and Siri suggestions.
    static var isDiscoverable = false

    @Parameter(title: "Person")
    var person: PocketVoicePersonEntity?

    init() {}

    init(person: PocketVoicePersonEntity?) {
        self.person = person
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$person)")
    }

    func perform() async throws -> some IntentResult {
        // The widget extension cannot play sound. If iOS ever runs us there, say so in the log.
        guard !PocketVoiceShared.isRunningInExtension else {
            PocketVoiceShared.appendLog("Widget play: ran in widget extension, cannot play audio here")
            return .result()
        }

        do {
            try await PocketVoiceAudioPlayback.toggle(personID: person?.personID, reloadWidgets: false)
        } catch {
            PocketVoiceShared.appendLog("Widget play: failed \(error)")
            throw error
        }
        return .result()
    }
}
