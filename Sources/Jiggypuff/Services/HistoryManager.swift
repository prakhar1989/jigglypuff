import Foundation

/// Represents a single transcription record
public struct TranscriptionItem: Identifiable, Codable, Sendable {
    public let id: UUID
    public let text: String
    public let timestamp: Date
    public let duration: TimeInterval
    public let model: String
    public let mode: String
    public let targetAppName: String?

    public init(id: UUID = UUID(),
                text: String,
                timestamp: Date = Date(),
                duration: TimeInterval,
                model: String,
                mode: String,
                targetAppName: String? = nil) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.duration = duration
        self.model = model
        self.mode = mode
        self.targetAppName = targetAppName
    }
}

/// Stores and retrieves transcription history in Application Support
@MainActor
public final class HistoryManager: ObservableObject {
    public static let shared = HistoryManager()

    @Published public var items: [TranscriptionItem] = []

    private let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let jiggypuffDir = appSupport.appendingPathComponent("Jiggypuff", isDirectory: true)

        try? FileManager.default.createDirectory(at: jiggypuffDir, withIntermediateDirectories: true, attributes: nil)
        self.fileURL = jiggypuffDir.appendingPathComponent("history.json")

        loadHistory()
    }

    public func add(item: TranscriptionItem) {
        items.insert(item, at: 0)
        // Keep last 200 items
        if items.count > 200 {
            items = Array(items.prefix(200))
        }
        saveHistory()
    }

    public func delete(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        saveHistory()
    }

    public func delete(item: TranscriptionItem) {
        items.removeAll(where: { $0.id == item.id })
        saveHistory()
    }

    public func clearAll() {
        items.removeAll()
        saveHistory()
    }

    private func saveHistory() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save history: \(error.localizedDescription)")
        }
    }

    private func loadHistory() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            self.items = try JSONDecoder().decode([TranscriptionItem].self, from: data)
        } catch {
            print("Failed to load history: \(error.localizedDescription)")
        }
    }
}
