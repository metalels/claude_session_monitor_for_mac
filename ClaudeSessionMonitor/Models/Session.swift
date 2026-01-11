import Foundation

struct Session: Identifiable, Hashable {
    let id: UUID
    let projectId: String
    let filePath: URL
    var lastModified: Date
    var summary: String?
    var messageCount: Int

    init(filePath: URL, projectId: String) {
        // Extract UUID from filename (e.g., "abc123-def456-...-xyz.jsonl")
        let filename = filePath.deletingPathExtension().lastPathComponent
        self.id = UUID(uuidString: filename) ?? UUID()
        self.projectId = projectId
        self.filePath = filePath
        self.messageCount = 0

        // Get file modification date
        if let attributes = try? FileManager.default.attributesOfItem(atPath: filePath.path),
           let modDate = attributes[.modificationDate] as? Date {
            self.lastModified = modDate
        } else {
            self.lastModified = Date()
        }
    }

    var displayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        let dateStr = formatter.string(from: lastModified)

        if let summary = summary, !summary.isEmpty {
            let truncated = summary.prefix(30)
            return "\(dateStr) - \(truncated)"
        }
        return "\(dateStr) - \(id.uuidString.prefix(8))..."
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.id == rhs.id
    }
}
