import Foundation
import os

// MARK: - EconomyOutbox
//
// Durable, per-user queue of economy events (flag ON only). One JSON file per
// user id in Application Support (not UserDefaults), written atomically on
// every change so an `event_key` survives an app kill and is reused on retry.
// An outbox is bound to the user id it was opened for; the service never
// sends one user's events while another user is signed in.

final class EconomyOutbox {
    let userID: String
    let fileURL: URL
    private(set) var events: [EconomyEvent]

    private static let log = Logger(subsystem: "com.perfecttap.app", category: "EconomyOutbox")

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("PerfectTapEconomy", isDirectory: true)
    }

    /// File-name-safe form of a user id (Supabase ids are lowercase UUIDs).
    static func fileName(for userID: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        let safe = String(userID.lowercased().filter { allowed.contains($0) })
        return "outbox-\(safe.isEmpty ? "invalid" : safe).json"
    }

    init(userID: String, directory: URL = EconomyOutbox.defaultDirectory) {
        self.userID = userID
        self.fileURL = directory.appendingPathComponent(Self.fileName(for: userID))
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? Self.decoder.decode([EconomyEvent].self, from: data) {
            events = decoded
        } else {
            events = []
        }
    }

    var isEmpty: Bool { events.isEmpty }

    /// Sum of the estimated coins of queued events (shown as "pending").
    var pendingCoins: Int { events.reduce(0) { $0 + max(0, $1.estimatedCoins) } }

    func contains(_ eventKey: UUID) -> Bool { events.contains { $0.eventKey == eventKey } }

    /// Appends and persists. Returns false when the write failed (the event is
    /// then still held in memory for this session and retried on next write).
    @discardableResult
    func enqueue(_ event: EconomyEvent) -> Bool {
        guard !contains(event.eventKey) else { return true }
        events.append(event)
        return persist()
    }

    @discardableResult
    func remove(_ eventKey: UUID) -> Bool {
        let before = events.count
        events.removeAll { $0.eventKey == eventKey }
        return before == events.count ? true : persist()
    }

    @discardableResult
    func update(_ event: EconomyEvent) -> Bool {
        guard let index = events.firstIndex(where: { $0.eventKey == event.eventKey }) else { return false }
        events[index] = event
        return persist()
    }

    private func persist() -> Bool {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if events.isEmpty {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
                return true
            }
            let data = try Self.encoder.encode(events)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            Self.log.error("outbox persist failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
