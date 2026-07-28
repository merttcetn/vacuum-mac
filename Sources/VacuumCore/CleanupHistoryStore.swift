import Foundation

public actor CleanupHistoryStore {
    private let fileURL: URL
    private let calendar: Calendar
    private var cached: [CleanupRecord]?

    public init(fileURL: URL, calendar: Calendar = .current) {
        self.fileURL = fileURL
        self.calendar = calendar
    }

    public func records(now: Date = .now) -> [CleanupRecord] {
        var values = load()
        let cutoff = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        var changed = false
        for index in values.indices where values[index].createdAt < cutoff {
            if values[index].originalURL != nil || values[index].trashURL != nil {
                values[index].originalURL = nil
                values[index].trashURL = nil
                values[index].detail = "Path details expired after 30 days."
                changed = true
            }
        }
        if changed { save(values) }
        return values.sorted { $0.createdAt > $1.createdAt }
    }

    public func record(id: UUID) -> CleanupRecord? {
        records().first { $0.id == id }
    }

    public func append(_ record: CleanupRecord) {
        var values = load()
        values.append(record)
        save(values)
    }

    public func replace(_ record: CleanupRecord) {
        var values = load()
        if let index = values.firstIndex(where: { $0.id == record.id }) {
            values[index] = record
        } else {
            values.append(record)
        }
        save(values)
    }

    private func load() -> [CleanupRecord] {
        if let cached { return cached }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([CleanupRecord].self, from: data)
        else {
            cached = []
            return []
        }
        cached = decoded
        return decoded
    }

    private func save(_ records: [CleanupRecord]) {
        cached = records
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(records).write(to: fileURL, options: .atomic)
        } catch {
            // History persistence must never turn a safe filesystem action into a crash.
        }
    }
}
