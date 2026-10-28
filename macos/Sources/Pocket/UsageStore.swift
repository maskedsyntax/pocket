import Foundation

/// Remembers how often and how recently each app was launched, so frequently
/// used apps float to the top of both search results and the empty view.
final class UsageStore {
    struct Record: Codable {
        var count: Int
        var lastUsed: Date
    }

    private var records: [String: Record]
    private let file: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pocket", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        file = support.appendingPathComponent("usage.json")

        if let data = try? Data(contentsOf: file),
            let decoded = try? JSONDecoder().decode([String: Record].self, from: data)
        {
            records = decoded
        } else {
            records = [:]
        }
    }

    func record(_ app: AppEntry) {
        var entry = records[app.id] ?? Record(count: 0, lastUsed: .distantPast)
        entry.count += 1
        entry.lastUsed = Date()
        records[app.id] = entry
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: file, options: .atomic)
        }
    }

    /// A bonus that nudges ranking without overriding match quality: a prefix
    /// match on a never-used app still beats a fuzzy match on a favourite.
    func boost(for app: AppEntry) -> Int {
        guard let entry = records[app.id] else { return 0 }
        let days = Date().timeIntervalSince(entry.lastUsed) / 86_400
        let recency = max(0, 200 - Int(days * 10))
        return min(entry.count, 40) * 10 + recency
    }

    func lastUsed(_ app: AppEntry) -> Date? {
        records[app.id]?.lastUsed
    }
}
