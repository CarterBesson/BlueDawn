import Foundation

struct TimelineMeta: Codable {
    var mastodonBottomCursor: String?
    var blueskyBottomCursor: String?
    var mastodonNewestID: String?
    var anchorPostID: String?
    var lastSaved: Date
}

struct PersistedTimeline: Codable {
    var posts: [UnifiedPost]
    var meta: TimelineMeta
}

enum TimelinePersistence {
    private static func supportDirectory() -> URL? {
        let fm = FileManager.default
        if let url = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            // Ensure subdirectory exists
            let appDir = url.appendingPathComponent("BlueDawn", isDirectory: true)
            if !fm.fileExists(atPath: appDir.path) {
                try? fm.createDirectory(at: appDir, withIntermediateDirectories: true)
            }
            return appDir
        }
        return nil
    }

    private static func fileURL() -> URL? {
        supportDirectory()?.appendingPathComponent("timeline.json")
    }

    static func load() -> PersistedTimeline? {
        guard let url = fileURL(), let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PersistedTimeline.self, from: data)
    }

    static func save(posts: [UnifiedPost], meta: TimelineMeta) {
        guard let url = fileURL() else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let state = PersistedTimeline(posts: posts, meta: meta)
        if let data = try? encoder.encode(state) {
            try? data.write(to: url, options: [.atomic])
        }
    }
}
