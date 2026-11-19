import AppIntents
import ImageIO
import SwiftUI
import UIKit
import WidgetKit

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

struct PocketVoiceEntry: TimelineEntry {
    let date: Date
    let people: [PocketVoicePerson?]
    var playingPersonID: String? = nil
    /// How many people are saved in the app, to tell "add someone in the app"
    /// apart from "choose someone in Edit Widget" when the widget is empty.
    var registeredCount: Int = 0
}

struct PocketVoiceProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PocketVoiceEntry {
        PocketVoiceEntry(
            date: .now,
            people: [
                PocketVoicePerson(
                    id: "placeholder",
                    name: "엄마",
                    photoFileName: nil,
                    audioFileName: nil,
                    createdAt: .now
                )
            ],
            registeredCount: 1
        )
    }

    func snapshot(for configuration: PocketVoiceWidgetConfigurationIntent, in context: Context) async -> PocketVoiceEntry {
        let allPeople = PocketVoiceStore.loadPeople()
        return PocketVoiceEntry(
            date: .now,
            people: selectedPeople(from: configuration, allPeople: allPeople),
            registeredCount: allPeople.count
        )
    }

    func timeline(for configuration: PocketVoiceWidgetConfigurationIntent, in context: Context) async -> Timeline<PocketVoiceEntry> {
        let allPeople = PocketVoiceStore.loadPeople()
        let people = selectedPeople(from: configuration, allPeople: allPeople)
        let count = allPeople.count
        var entries: [PocketVoiceEntry] = []

        // While a voice plays, show a stop button until the clip ends,
        // then switch back to play even if the app never gets to reload us.
        if let nowPlaying = PocketVoiceShared.nowPlaying {
            entries.append(PocketVoiceEntry(date: .now, people: people, playingPersonID: nowPlaying.personID, registeredCount: count))
            entries.append(PocketVoiceEntry(date: nowPlaying.until, people: people, registeredCount: count))
        } else {
            entries.append(PocketVoiceEntry(date: .now, people: people, registeredCount: count))
        }

        return Timeline(entries: entries, policy: .after(.now.addingTimeInterval(60 * 30)))
    }

    /// People chosen in Edit Widget, in slot order. With nothing chosen yet
    /// (a freshly added widget), fills in the app's people in their saved order.
    private func selectedPeople(
        from configuration: PocketVoiceWidgetConfigurationIntent,
        allPeople people: [PocketVoicePerson]
    ) -> [PocketVoicePerson?] {
        let slots = [
            configuration.firstPerson,
            configuration.secondPerson,
            configuration.thirdPerson,
            configuration.fourthPerson
        ]

        guard slots.contains(where: { $0 != nil }) else {
            return people.map(Optional.some)
        }

        var usedIDs = Set<String>()
        return slots.map { entity -> PocketVoicePerson? in
            guard let entity else { return nil }
            guard entity.id != PocketVoicePersonEntity.emptyID else { return nil }
            guard !usedIDs.contains(entity.id),
                  let person = people.first(where: { $0.id == entity.id }) else {
                return nil
            }
            usedIDs.insert(entity.id)
            return person
        }
    }
}

struct PocketVoiceWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: PocketVoiceEntry

    var body: some View {
        let people = visiblePeople

        // visiblePeople is padded with empty slots, so check what would actually show.
        if people.allSatisfy({ $0 == nil }) {
            emptyState
        } else {
            GeometryReader { proxy in
                content(for: people, size: proxy.size)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
            }
            .ignoresSafeArea()
            .containerBackground(for: .widget) {
                widgetBackground
            }
        }
    }

    private var visiblePeople: [PocketVoicePerson?] {
        let people = Array(entry.people.prefix(maxPeople))
        guard people.count < maxPeople else { return people }
        return people + Array(repeating: nil, count: maxPeople - people.count)
    }

    private var maxPeople: Int {
        switch family {
        case .systemLarge:
            4
        case .systemMedium:
            2
        default:
            1
        }
    }

    @ViewBuilder
    private func content(for people: [PocketVoicePerson?], size: CGSize) -> some View {
        switch family {
        case .systemLarge:
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    largeCell(at: 0, people: people)
                    largeCell(at: 1, people: people)
                }
                HStack(spacing: 0) {
                    largeCell(at: 2, people: people)
                    largeCell(at: 3, people: people)
                }
            }
            .frame(width: size.width, height: size.height)
            .background(widgetBackground)
        case .systemMedium:
            HStack(spacing: 0) {
                ForEach(Array(people.enumerated()), id: \.offset) { _, person in
                    if let person {
                        personTile(person, compact: false)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        blankTile
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .background(widgetBackground)
        default:
            if let person = people.first, let person {
                personTile(person, compact: false)
                    .frame(width: size.width, height: size.height)
            } else {
                blankTile
                    .frame(width: size.width, height: size.height)
            }
        }
    }

    @ViewBuilder
    private func largeCell(at index: Int, people: [PocketVoicePerson?]) -> some View {
        if index < people.count, let person = people[index] {
            personTile(person, compact: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            blankTile
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func personTile(_ person: PocketVoicePerson, compact: Bool) -> some View {
        GeometryReader { proxy in
            ZStack {
                background(for: person, size: proxy.size)
                overlay(for: person, compact: compact)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private func background(for person: PocketVoicePerson, size: CGSize) -> some View {
        ZStack {
            if let image = widgetImage(for: person, size: size) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                LinearGradient(colors: [Color(hex: 0xFFE04D), Color(hex: 0xFFC400), Color(hex: 0xF6A900)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(width: size.width, height: size.height)
                Text(String(person.name.prefix(1)))
                    .font(.custom("Paperlogy-7Bold", size: 74))
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .overlay(.black.opacity(0.16))
    }

    private func widgetImage(for person: PocketVoicePerson, size: CGSize) -> UIImage? {
        guard let data = PocketVoiceStore.photoData(for: person) else { return nil }
        let maxDimension = max(size.width, size.height, 180) * 2
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }

    private func overlay(for person: PocketVoicePerson, compact: Bool) -> some View {
        VStack {
            HStack {
                Text(person.name)
                    .font(.custom("Paperlogy-6SemiBold", size: compact ? 12 : (family == .systemMedium ? 15 : 13)))
                    .foregroundStyle(.white)
                    .padding(.horizontal, compact ? 8 : (family == .systemMedium ? 10 : 9))
                    .padding(.vertical, compact ? 5 : (family == .systemMedium ? 6 : 5))
                    .background(.black.opacity(0.28), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
                    .lineLimit(1)
                Spacer()
            }

            Spacer()

            HStack {
                Spacer()
                if person.hasAudio {
                    // Plays in the background through the app process; the home screen stays put.
                    Button(intent: PlayPersonVoiceIntent(person: PocketVoicePersonEntity(person: person))) {
                        playIcon(for: person, compact: compact)
                    }
                    .buttonStyle(.plain)
                } else {
                    playIcon(for: person, compact: compact)
                        .opacity(0.62)
                }
            }
        }
        .padding(compact ? 10 : (family == .systemMedium ? 12 : 12))
    }

    private func playIcon(for person: PocketVoicePerson, compact: Bool) -> some View {
        let isPlaying = person.hasAudio && entry.playingPersonID == person.id
        return Image(systemName: isPlaying ? "stop.fill" : (person.hasAudio ? "play.fill" : "mic.slash.fill"))
            .font(compact ? .caption : (family == .systemMedium ? .headline : .headline))
            .foregroundStyle(person.hasAudio ? Color(hex: 0xEF2B24) : Color(hex: 0xEF2B24).opacity(0.58))
            .frame(width: compact ? 36 : (family == .systemMedium ? 46 : 42), height: compact ? 36 : (family == .systemMedium ? 46 : 42))
            .background(.white.opacity(person.hasAudio ? 0.98 : 0.7), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 1))
            .accessibilityLabel(playIconLabel(hasAudio: person.hasAudio, isPlaying: isPlaying))
    }

    private func playIconLabel(hasAudio: Bool, isPlaying: Bool) -> String {
        if PocketVoiceShared.isEnglish {
            return isPlaying ? "Stop" : (hasAudio ? "Play" : "Recording needed")
        }
        return isPlaying ? "정지" : (hasAudio ? "재생" : "녹음 필요")
    }

    private var emptyState: some View {
        let needsPeopleInApp = entry.registeredCount == 0
        return VStack(spacing: family == .systemSmall ? 8 : 10) {
            Image(systemName: needsPeopleInApp ? "person.crop.circle.badge.plus" : "hand.tap.fill")
                .font(.system(size: family == .systemSmall ? 28 : 32))
            Text(needsPeopleInApp ? addInAppMessage : editWidgetMessage)
                .font(.custom("Paperlogy-6SemiBold", size: family == .systemSmall ? 12 : 14))
                .lineLimit(4)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
                .padding(.horizontal, family == .systemSmall ? 12 : 24)
        }
        .foregroundStyle(Color(hex: 0x3A2500))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            widgetBackground
        }
    }

    /// No one saved in the app yet.
    private var addInAppMessage: String {
        PocketVoiceShared.isEnglish
            ? "Tap to add a person in Pocket Voice."
            : "눌러서 앱에서 인물을 먼저 등록해주세요."
    }

    /// People exist, but none is chosen for the visible slots.
    private var editWidgetMessage: String {
        PocketVoiceShared.isEnglish
            ? "Touch and hold the widget, then choose people in Edit Widget."
            : "위젯을 길게 눌러 '위젯 편집'에서 인물을 선택해주세요."
    }

    private var blankTile: some View {
        ZStack {
            widgetBackground
            Circle()
                .fill(.white.opacity(0.15))
                .frame(width: 96, height: 96)
                .blur(radius: 12)
            Image(systemName: "plus")
                .font(.system(size: family == .systemLarge ? 18 : 24, weight: .bold))
                .foregroundStyle(Color(hex: 0x3A2500).opacity(0.48))
        }
        .clipped()
    }

    private var widgetBackground: some View {
        LinearGradient(
            colors: [Color(hex: 0xFFE04D), Color(hex: 0xFFC400), Color(hex: 0xF6A900)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct PocketVoiceWidget: Widget {
    let kind = "PocketVoicePersonWidgetV4"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: PocketVoiceWidgetConfigurationIntent.self,
            provider: PocketVoiceProvider()
        ) { entry in
            PocketVoiceWidgetView(entry: entry)
        }
        .configurationDisplayName("Pocket Voice")
        .description("Select people to add to the widget.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct PocketVoiceWidgetBundle: WidgetBundle {
    var body: some Widget {
        PocketVoiceWidget()
    }
}
