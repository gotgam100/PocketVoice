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
            ]
        )
    }

    func snapshot(for configuration: PocketVoiceWidgetConfigurationIntent, in context: Context) async -> PocketVoiceEntry {
        PocketVoiceEntry(date: .now, people: selectedPeople(from: configuration))
    }

    func timeline(for configuration: PocketVoiceWidgetConfigurationIntent, in context: Context) async -> Timeline<PocketVoiceEntry> {
        Timeline(
            entries: [PocketVoiceEntry(date: .now, people: selectedPeople(from: configuration))],
            policy: .after(.now.addingTimeInterval(60 * 30))
        )
    }

    private func selectedPeople(from configuration: PocketVoiceWidgetConfigurationIntent) -> [PocketVoicePerson?] {
        let people = PocketVoiceStore.loadPeople()
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

        if people.isEmpty {
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
        Array(entry.people.prefix(maxPeople))
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
                Link(destination: PocketVoiceShared.homeURL) {
                    Color.clear
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                overlay(for: person, compact: compact)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private func background(for person: PocketVoicePerson, size: CGSize) -> some View {
        ZStack {
            if let data = PocketVoiceStore.photoData(for: person), let image = UIImage(data: data) {
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
                    Link(destination: PocketVoiceShared.autoplayURL(for: person.id)) {
                        playIcon(for: person, compact: compact)
                    }
                } else {
                    playIcon(for: person, compact: compact)
                        .opacity(0.62)
                }
            }
        }
        .padding(compact ? 10 : (family == .systemMedium ? 12 : 12))
    }

    private func playIcon(for person: PocketVoicePerson, compact: Bool) -> some View {
        Image(systemName: person.hasAudio ? "play.fill" : "mic.slash.fill")
            .font(compact ? .caption : (family == .systemMedium ? .headline : .headline))
            .foregroundStyle(Color(hex: person.category.accent.hex))
            .frame(width: compact ? 36 : (family == .systemMedium ? 46 : 42), height: compact ? 36 : (family == .systemMedium ? 46 : 42))
            .background(Color(hex: 0xF6F3EC).opacity(person.hasAudio ? 0.96 : 0.62), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.42), lineWidth: 1))
            .accessibilityLabel(person.hasAudio ? "재생" : "녹음 필요")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 32))
            Text("위젯에 등록할 인물을 선택해주세요.")
                .font(.custom("Paperlogy-6SemiBold", size: 12))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
        }
        .foregroundStyle(Color(hex: 0x3A2500))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            widgetBackground
        }
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
        .description("위젯에 등록할 인물을 선택해주세요.")
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
