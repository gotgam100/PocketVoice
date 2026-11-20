import StoreKit
import SwiftUI

/// Pocket Voice Plus: a one-time purchase (non-consumable) that removes the
/// free version's people limit and allows longer recordings.
///
/// People who first installed 1.0 (build "1") get Plus for free; 2.0 is build "2". Apple's
/// AppTransaction tells us the build they first downloaded, which survives
/// reinstalling and switching devices on the same Apple ID.
@MainActor
final class PocketVoicePlus: ObservableObject {
    static let shared = PocketVoicePlus()

    nonisolated static let productID = "com.baekmac.pocketvoice.plus"
    nonisolated static let freePeopleLimit = 4
    nonisolated static let freeRecordingSeconds: TimeInterval = 10
    nonisolated static let plusRecordingSeconds: TimeInterval = 60

    nonisolated private static let purchasedKey = "pocketvoice.plus.purchased"
    nonisolated private static let earlyUserKey = "pocketvoice.plus.earlyUser"

    @Published private(set) var product: Product?
    @Published private(set) var isPurchased: Bool
    @Published private(set) var isEarlyUser: Bool
    @Published private(set) var isPurchasing = false
    @Published var message: String?

    private var updatesTask: Task<Void, Never>?

    var isActive: Bool {
        isPurchased || isEarlyUser
    }

    /// Last known Plus state, readable from anywhere (e.g. a view's init).
    nonisolated static var cachedIsActive: Bool {
        let defaults = UserDefaults.standard
        return defaults.bool(forKey: purchasedKey) || defaults.bool(forKey: earlyUserKey)
    }

    /// The App Store's localized price, or the Korean base price before it loads.
    var displayPrice: String {
        #if DEBUG
        // Screenshots: -PocketVoiceScreenshotPrice '$0.49' shows another storefront's price.
        if let price = UserDefaults.standard.string(forKey: "PocketVoiceScreenshotPrice") {
            return price
        }
        #endif
        return product?.displayPrice ?? "₩1,100"
    }

    nonisolated static func recordingSeconds(isPlus: Bool) -> TimeInterval {
        isPlus ? plusRecordingSeconds : freeRecordingSeconds
    }

    private init() {
        isPurchased = UserDefaults.standard.bool(forKey: Self.purchasedKey)
        isEarlyUser = UserDefaults.standard.bool(forKey: Self.earlyUserKey)
    }

    /// Call once at launch: listens for purchases made elsewhere (other
    /// devices, Ask to Buy, refunds) and refreshes the current state.
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlement()
            }
        }
        Task { await refresh() }
    }

    func refresh() async {
        await refreshEntitlement()
        await refreshEarlyUser()
        if product == nil {
            await loadProduct()
        }
    }

    func purchase() async {
        if product == nil {
            await loadProduct()
        }
        guard let product else {
            message = Self.text("구매 정보를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.",
                                "Couldn't load the purchase. Please try again later.")
            return
        }

        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    message = Self.text("구매를 확인하지 못했어요.", "Couldn't verify the purchase.")
                    return
                }
                await transaction.finish()
                setPurchased(true)
            case .pending:
                message = Self.text("구매 승인을 기다리고 있어요. 승인되면 바로 적용돼요.",
                                    "Waiting for approval. Plus turns on as soon as it's approved.")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func restore() async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
        } catch {
            message = error.localizedDescription
            return
        }
        await refreshEntitlement()
        await refreshEarlyUser()
        message = isActive
            ? Self.text("Pocket Voice Plus가 복원됐어요.", "Pocket Voice Plus has been restored.")
            : Self.text("복원할 구매 내역이 없어요.", "No purchase to restore.")
    }

    private func loadProduct() async {
        product = try? await Product.products(for: [Self.productID]).first
    }

    private func refreshEntitlement() async {
        #if DEBUG
        // Preview the paid state without buying: launch argument -PocketVoicePlusPurchased YES.
        if UserDefaults.standard.bool(forKey: "PocketVoicePlusPurchased") {
            setPurchased(true)
            return
        }
        #endif
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        setPurchased(owned)
    }

    private func refreshEarlyUser() async {
        #if DEBUG
        // Test the existing-user path with the launch argument -PocketVoiceEarlyUser YES.
        if UserDefaults.standard.bool(forKey: "PocketVoiceEarlyUser") {
            setEarlyUser(true)
            return
        }
        #endif

        // If Apple can't be reached, keep the last known answer.
        guard let result = try? await AppTransaction.shared,
              case .verified(let transaction) = result else {
            return
        }
        // Only real App Store installs count. Xcode and TestFlight installs
        // report made-up first builds and dates, which could look like 1.0.
        guard transaction.environment == .production else {
            setEarlyUser(false)
            return
        }
        // Once granted in the App Store build, the gift stays.
        guard !isEarlyUser else { return }
        // 1.0 was build "1". 2.0, the first version with Plus, is build "2",
        // so any later first build means a new user. Keep future builds above "1".
        setEarlyUser(transaction.originalAppVersion == "1")
    }

    private func setPurchased(_ value: Bool) {
        isPurchased = value
        UserDefaults.standard.set(value, forKey: Self.purchasedKey)
    }

    private func setEarlyUser(_ value: Bool) {
        isEarlyUser = value
        UserDefaults.standard.set(value, forKey: Self.earlyUserKey)
    }

    private static func text(_ korean: String, _ english: String) -> String {
        PocketVoiceShared.isEnglish ? english : korean
    }
}

/// The Plus sheet, shown when a free user tries to add a 5th person and from Settings.
struct PocketVoicePlusView: View {
    enum Reason {
        case peopleLimit
        case settings
    }

    let reason: Reason

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var plus = PocketVoicePlus.shared
    @AppStorage(PocketVoiceShared.languageKey) private var languageRaw = "ko"

    private var english: Bool { languageRaw == "en" }

    private let ink = Color(red: 0x3A / 255, green: 0x25 / 255, blue: 0)
    private let red = Color(red: 0xEF / 255, green: 0x2B / 255, blue: 0x24 / 255)
    private let cream = Color(red: 1, green: 0xF3 / 255, blue: 0xAF / 255)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(red)
                        .padding(.top, 12)

                    VStack(spacing: 8) {
                        Text("Pocket Voice Plus")
                            .font(.custom("Paperlogy-7Bold", size: 28, relativeTo: .title))
                            .foregroundStyle(ink)
                        Text(headline)
                            .font(.custom("Paperlogy-5Medium", size: 15, relativeTo: .body))
                            .foregroundStyle(ink.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        feature(
                            symbol: "person.3.fill",
                            title: english ? "Add as many people as you like" : "인물 수 제한 없이 등록",
                            detail: english ? "Free version: up to \(PocketVoicePlus.freePeopleLimit) people" : "무료 버전은 \(PocketVoicePlus.freePeopleLimit)명까지"
                        )
                        feature(
                            symbol: "waveform",
                            title: english ? "Record up to 1 minute" : "최대 1분까지 녹음",
                            detail: english ? "Free version: up to 10 seconds" : "무료 버전은 10초까지"
                        )
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18))

                    if plus.isActive {
                        Label(activeText, systemImage: "checkmark.seal.fill")
                            .font(.custom("Paperlogy-7Bold", size: 16, relativeTo: .body))
                            .foregroundStyle(ink)
                            .multilineTextAlignment(.center)
                    } else {
                        Button {
                            Task { await plus.purchase() }
                        } label: {
                            Group {
                                if plus.isPurchasing {
                                    ProgressView().tint(.white)
                                } else {
                                    Text(buyTitle)
                                }
                            }
                            .font(.custom("Paperlogy-7Bold", size: 17, relativeTo: .body))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(red, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(plus.isPurchasing)

                        Button(english ? "Restore Purchase" : "구매 복원") {
                            Task { await plus.restore() }
                        }
                        .font(.custom("Paperlogy-5Medium", size: 14, relativeTo: .body))
                        .foregroundStyle(ink.opacity(0.7))
                        .disabled(plus.isPurchasing)
                    }

                    Text(english
                         ? "A one-time purchase, not a subscription. It also works on your other devices signed in to the same Apple Account."
                         : "구독이 아닌 한 번 결제예요. 같은 Apple 계정을 쓰는 다른 기기에서도 사용할 수 있어요.")
                        .font(.custom("Paperlogy-5Medium", size: 12, relativeTo: .footnote))
                        .foregroundStyle(ink.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }
            .background(cream)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(ink)
                    }
                }
            }
            .alert(
                "Pocket Voice Plus",
                isPresented: Binding(get: { plus.message != nil }, set: { if !$0 { plus.message = nil } })
            ) {
                Button("OK") {
                    plus.message = nil
                }
            } message: {
                Text(plus.message ?? "")
            }
            .task {
                await plus.refresh()
            }
        }
    }

    private var headline: String {
        switch reason {
        case .peopleLimit:
            english
                ? "The free version holds up to \(PocketVoicePlus.freePeopleLimit) people.\nUpgrade once to add more."
                : "무료 버전은 \(PocketVoicePlus.freePeopleLimit)명까지 등록할 수 있어요.\n한 번 구매로 더 많은 목소리를 담아보세요."
        case .settings:
            english ? "More people and longer voices, with one purchase." : "한 번 구매로 더 많은 사람, 더 긴 목소리를."
        }
    }

    private var buyTitle: String {
        let price = plus.displayPrice
        return english ? "Buy for \(price)" : "\(price)에 구매하기"
    }

    private var activeText: String {
        if plus.isEarlyUser && !plus.isPurchased {
            return english ? "Free for you as an early user. Thank you!" : "기존 사용자 혜택으로 무료로 사용 중이에요"
        }
        return english ? "You're using Plus" : "Plus를 사용 중이에요"
    }

    private func feature(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(red)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.custom("Paperlogy-7Bold", size: 16, relativeTo: .body))
                    .foregroundStyle(ink)
                Text(detail)
                    .font(.custom("Paperlogy-5Medium", size: 13, relativeTo: .footnote))
                    .foregroundStyle(ink.opacity(0.55))
            }
        }
    }
}
