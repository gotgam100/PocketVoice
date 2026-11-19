import Foundation
import UIKit
import WidgetKit

/// Keeps people, photos and voices in the user's own iCloud Drive (the app's
/// hidden ubiquity container). Free for everyone and fully automatic:
/// - leaving the app backs up whatever changed;
/// - opening the app loads a newer backup made on another device
///   (e.g. a new iPhone on the same Apple Account). The newest change wins.
enum PocketVoiceBackup {
    static let containerID = "iCloud.com.baekmac.pocketvoice"
    static let lastBackupKey = "pocketvoice.backup.lastDate"
    private static let deviceIDKey = "pocketvoice.backup.deviceID"
    /// Set once this install has backed up or loaded a backup at least once.
    private static let hasSyncedKey = "pocketvoice.backup.hasSynced"

    /// Posted on the main thread after a backup from another device was loaded.
    static let didRestoreNotification = Notification.Name("PocketVoiceBackupDidRestore")

    private static let peopleFileName = "people.json"
    private static let infoFileName = "backup-info.json"

    struct Info: Codable, Equatable {
        var date: Date
        var peopleCount: Int
        var appVersion: String
        /// Which install made the backup, so a device never "restores" its own backup.
        var deviceID: String?
    }

    enum BackupError: Error, LocalizedError {
        case iCloudUnavailable
        case noBackup
        case downloadTimedOut

        var errorDescription: String? {
            let english = PocketVoiceShared.isEnglish
            return switch self {
            case .iCloudUnavailable:
                english ? "Sign in to iCloud and turn on iCloud Drive to back up." : "iCloud에 로그인하고 iCloud Drive를 켜야 백업할 수 있어요."
            case .noBackup:
                english ? "There's no backup in iCloud yet." : "iCloud에 저장된 백업이 없어요."
            case .downloadTimedOut:
                english ? "Couldn't download the backup from iCloud. Check your connection and try again." : "iCloud에서 백업을 받아오지 못했어요. 인터넷 연결을 확인하고 다시 시도해 주세요."
            }
        }
    }

    /// Backup and loading never run at the same time (e.g. leaving and
    /// reopening the app quickly).
    @MainActor private static var isSyncing = false

    static var isICloudSignedIn: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    static var lastBackupDate: Date? {
        UserDefaults.standard.object(forKey: lastBackupKey) as? Date
    }

    // MARK: - Backup

    @discardableResult
    static func backup() async throws -> Info {
        try await Task.detached(priority: .utility) {
            try backupNow()
        }.value
    }

    /// Backs up when the app goes to the background, if anything changed since the last backup.
    @MainActor
    static func autoBackupIfNeeded() {
        guard isICloudSignedIn, !isSyncing, hasChangesSinceLastBackup else { return }
        isSyncing = true

        var taskID = UIBackgroundTaskIdentifier.invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: "PocketVoiceBackup") {
            UIApplication.shared.endBackgroundTask(taskID)
            taskID = .invalid
        }
        Task {
            do {
                try await backup()
            } catch {
                PocketVoiceShared.appendLog("Auto backup failed: \(error.localizedDescription)")
            }
            isSyncing = false
            if taskID != .invalid {
                UIApplication.shared.endBackgroundTask(taskID)
                taskID = .invalid
            }
        }
    }

    /// Loads the iCloud backup when it is newer than what's on this iPhone and
    /// came from another device, or when this iPhone has no data yet.
    /// Call when the app becomes active.
    @MainActor
    static func loadFromOtherDeviceIfNeeded() async {
        guard isICloudSignedIn, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            guard let info = try await latestBackupInfo() else { return }
            let localDate = localPeopleModificationDate
            let isOtherDevice = info.deviceID != deviceID
            let shouldLoad = localDate == nil
                || (isOtherDevice && info.date > (localDate ?? .distantPast))
            guard shouldLoad, info.peopleCount > 0 || localDate != nil else { return }
            try await restore(keepLocalPeople: !hasSynced)
            NotificationCenter.default.post(name: didRestoreNotification, object: nil)
        } catch {
            PocketVoiceShared.appendLog("iCloud load failed: \(error.localizedDescription)")
        }
    }

    /// A random ID for this install of the app.
    private static var deviceID: String {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: deviceIDKey) {
            return id
        }
        let id = UUID().uuidString
        defaults.set(id, forKey: deviceIDKey)
        return id
    }

    private static var hasSynced: Bool {
        UserDefaults.standard.bool(forKey: hasSyncedKey)
    }

    private static var localPeopleModificationDate: Date? {
        (try? PocketVoiceStore.peopleFileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private static var hasChangesSinceLastBackup: Bool {
        let peopleURL = PocketVoiceStore.peopleFileURL
        guard let modified = (try? peopleURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else {
            return false
        }
        guard let last = lastBackupDate else { return true }
        return modified > last
    }

    private static func backupNow() throws -> Info {
        let folder = try backupFolder()
        let fileManager = FileManager.default

        // First backup from this install: if another device already backed up,
        // merge its people in first instead of overwriting them.
        if !hasSynced {
            let infoURL = folder.appendingPathComponent(infoFileName)
            if try downloadIfNeeded(infoURL),
               let info = try? JSONDecoder().decode(Info.self, from: Data(contentsOf: infoURL)),
               info.deviceID != deviceID {
                _ = try restoreNow(keepLocalPeople: true)
            }
        }
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let startedAt = Date()
        let people = PocketVoiceStore.loadPeople()
        let fileNames = Set(people.flatMap { [$0.photoFileName, $0.sourcePhotoFileName, $0.audioFileName].compactMap { $0 } })

        for name in fileNames {
            let source = PocketVoiceStore.fileURL(name)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = folder.appendingPathComponent(name)
            guard !isUnchanged(source: source, destination: destination) else { continue }
            try coordinatedWrite(to: destination) { url in
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                }
                try fileManager.copyItem(at: source, to: url)
            }
        }

        // Drop files of people who were deleted since the last backup.
        let keep = fileNames.union([peopleFileName, infoFileName])
        for url in (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            let name = url.lastPathComponent
            // iCloud placeholders look like ".name.icloud".
            let realName = name.hasPrefix(".") && name.hasSuffix(".icloud")
                ? String(name.dropFirst().dropLast(".icloud".count))
                : name
            if !keep.contains(realName) {
                try? coordinatedWrite(to: url) { try fileManager.removeItem(at: $0) }
            }
        }

        let info = Info(
            date: startedAt,
            peopleCount: people.count,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            deviceID: deviceID
        )
        let encoder = JSONEncoder()
        let peopleData = try encoder.encode(people)
        let infoData = try encoder.encode(info)
        try coordinatedWrite(to: folder.appendingPathComponent(peopleFileName)) { try peopleData.write(to: $0, options: .atomic) }
        try coordinatedWrite(to: folder.appendingPathComponent(infoFileName)) { try infoData.write(to: $0, options: .atomic) }

        UserDefaults.standard.set(startedAt, forKey: lastBackupKey)
        UserDefaults.standard.set(true, forKey: hasSyncedKey)
        return info
    }

    private static func isUnchanged(source: URL, destination: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let sourceValues = try? source.resourceValues(forKeys: keys),
              let destinationValues = try? destination.resourceValues(forKeys: keys),
              let sourceDate = sourceValues.contentModificationDate,
              let destinationDate = destinationValues.contentModificationDate else {
            return false
        }
        return sourceValues.fileSize == destinationValues.fileSize && sourceDate <= destinationDate
    }

    // MARK: - Restore

    /// Reads what the latest backup contains, without changing anything.
    static func latestBackupInfo() async throws -> Info? {
        try await Task.detached(priority: .utility) {
            let url = try backupFolder().appendingPathComponent(infoFileName)
            guard try downloadIfNeeded(url) else { return nil }
            return try JSONDecoder().decode(Info.self, from: Data(contentsOf: url))
        }.value
    }

    /// Replaces everything on this iPhone with the backup. Returns the number of people restored.
    /// Only called automatically, when a newer backup from another device exists.
    @discardableResult
    static func restore(keepLocalPeople: Bool) async throws -> Int {
        let count = try await Task.detached(priority: .userInitiated) {
            try restoreNow(keepLocalPeople: keepLocalPeople)
        }.value
        await MainActor.run {
            WidgetCenter.shared.reloadAllTimelines()
        }
        return count
    }

    /// `keepLocalPeople`: also keep people that exist only on this iPhone (first sync).
    private static func restoreNow(keepLocalPeople: Bool) throws -> Int {
        let folder = try backupFolder()
        let fileManager = FileManager.default
        let peopleURL = folder.appendingPathComponent(peopleFileName)
        guard try downloadIfNeeded(peopleURL) else {
            throw BackupError.noBackup
        }
        let backupPeople = try JSONDecoder().decode([PocketVoicePerson].self, from: Data(contentsOf: peopleURL))
        let backupNames = Set(backupPeople.flatMap { [$0.photoFileName, $0.sourcePhotoFileName, $0.audioFileName].compactMap { $0 } })

        try PocketVoiceStore.ensureContainerExists()
        for name in backupNames {
            let source = folder.appendingPathComponent(name)
            guard try downloadIfNeeded(source) else { continue }
            let destination = PocketVoiceStore.fileURL(name)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        }

        let current = PocketVoiceStore.loadPeople()
        let backupIDs = Set(backupPeople.map(\.id))
        let localOnly = keepLocalPeople ? current.filter { !backupIDs.contains($0.id) } : []
        var merged = backupPeople
        for (offset, person) in localOnly.enumerated() {
            var moved = person
            moved.sortOrder = backupPeople.count + offset
            merged.append(moved)
        }

        // Remove files of people on this iPhone who are no longer in the list.
        let keptNames = Set(merged.flatMap { [$0.photoFileName, $0.sourcePhotoFileName, $0.audioFileName].compactMap { $0 } })
        let currentNames = Set(current.flatMap { [$0.photoFileName, $0.sourcePhotoFileName, $0.audioFileName].compactMap { $0 } })
        for name in currentNames.subtracting(keptNames) {
            try? fileManager.removeItem(at: PocketVoiceStore.fileURL(name))
        }

        try PocketVoiceStore.savePeople(merged)
        UserDefaults.standard.set(true, forKey: hasSyncedKey)
        if localOnly.isEmpty {
            // What's on the phone now matches the backup.
            UserDefaults.standard.set(Date(), forKey: lastBackupKey)
        }
        return merged.count
    }

    // MARK: - iCloud helpers

    /// Blocks, so only call off the main thread.
    private static func backupFolder() throws -> URL {
        guard isICloudSignedIn,
              let container = FileManager.default.url(forUbiquityContainerIdentifier: containerID) else {
            throw BackupError.iCloudUnavailable
        }
        return container.appendingPathComponent("Documents/Backup", isDirectory: true)
    }

    /// Makes sure an iCloud file is on this device. Returns false if it doesn't exist in iCloud.
    private static func downloadIfNeeded(_ url: URL) throws -> Bool {
        if isDownloaded(url) {
            return true
        }
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            return false
        }
        for _ in 0..<120 {
            Thread.sleep(forTimeInterval: 0.5)
            if isDownloaded(url) {
                return true
            }
        }
        throw BackupError.downloadTimedOut
    }

    private static func isDownloaded(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let status = (try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus
        return status == nil || status == .current || status == .downloaded
    }

    private static func coordinatedWrite(to url: URL, _ work: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var workError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                try work(coordinatedURL)
            } catch {
                workError = error
            }
        }
        if let error = coordinationError ?? workError {
            throw error
        }
    }
}
