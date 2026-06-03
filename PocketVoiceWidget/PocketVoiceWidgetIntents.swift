import AppIntents
import Foundation

struct PocketVoicePersonEntity: AppEntity, Identifiable, Hashable {
    static let emptyID = "__pocketvoice_empty_slot__"
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "인물")
    static var defaultQuery = PocketVoicePersonQuery()

    let id: String

    @Property(title: "이름")
    var name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    var displayRepresentation: DisplayRepresentation {
        if id == Self.emptyID {
            return DisplayRepresentation(
                title: LocalizedStringResource(stringLiteral: "비워두기"),
                subtitle: LocalizedStringResource(stringLiteral: "선택 안 함")
            )
        }

        return DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }

    static func == (lhs: PocketVoicePersonEntity, rhs: PocketVoicePersonEntity) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private extension PocketVoicePersonEntity {
    static var emptySlot: PocketVoicePersonEntity {
        PocketVoicePersonEntity(id: emptyID, name: "비워두기")
    }
}

struct PocketVoicePersonQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [PocketVoicePersonEntity] {
        var entities = PocketVoiceStore.loadPeople()
            .filter { identifiers.contains($0.id) }
            .map { PocketVoicePersonEntity(id: $0.id, name: $0.name) }

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
            .map { PocketVoicePersonEntity(id: $0.id, name: $0.name) }

        if query.isEmpty || "비워두기".contains(query) || "선택 안 함".contains(query) || "empty".contains(query) || "none".contains(query) {
            return [PocketVoicePersonEntity.emptySlot] + people
        }

        return people
    }

    func suggestedEntities() async throws -> [PocketVoicePersonEntity] {
        [PocketVoicePersonEntity.emptySlot] + PocketVoiceStore.loadPeople()
            .map { PocketVoicePersonEntity(id: $0.id, name: $0.name) }
    }

    func defaultResult() async -> PocketVoicePersonEntity? {
        nil
    }
}

struct PocketVoiceWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Pocket Voice 위젯 설정"
    static var description = IntentDescription("위젯에 등록할 인물을 선택해주세요.")

    @Parameter(title: "첫 번째")
    var firstPerson: PocketVoicePersonEntity?

    @Parameter(title: "두 번째")
    var secondPerson: PocketVoicePersonEntity?

    @Parameter(title: "세 번째")
    var thirdPerson: PocketVoicePersonEntity?

    @Parameter(title: "네 번째")
    var fourthPerson: PocketVoicePersonEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("순서 \(\.$firstPerson), \(\.$secondPerson), \(\.$thirdPerson), \(\.$fourthPerson)")
    }
}

