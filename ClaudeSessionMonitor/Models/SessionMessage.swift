import Foundation

// MARK: - Message Type
enum MessageType: String, CaseIterable, Codable {
    case user
    case assistant
    case summary
    case fileHistorySnapshot = "file-history-snapshot"

    var displayName: String {
        switch self {
        case .user: return "User"
        case .assistant: return "Assistant"
        case .summary: return "Summary"
        case .fileHistorySnapshot: return "File History"
        }
    }
}

// MARK: - Content Block Types
enum ContentBlockType: String, Codable {
    case text
    case thinking
    case toolUse = "tool_use"
    case toolResult = "tool_result"
}

struct ContentBlock: Identifiable {
    let id = UUID()
    let type: ContentBlockType
    let text: String?
    let thinking: String?
    let toolName: String?
    let toolInput: String?

    var displayContent: String {
        switch type {
        case .text:
            return text ?? ""
        case .thinking:
            return "[Thinking] \(thinking ?? "")"
        case .toolUse:
            return "[Tool: \(toolName ?? "unknown")] \(toolInput?.prefix(200) ?? "")"
        case .toolResult:
            return "[Result] \(text?.prefix(200) ?? "")"
        }
    }
}

// MARK: - Session Message
struct SessionMessage: Identifiable {
    let id: String
    let type: MessageType
    let timestamp: Date
    let role: String?
    let model: String?
    let contentBlocks: [ContentBlock]
    let rawContent: String?

    var displayTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }

    var displayRole: String {
        switch type {
        case .user:
            return "User"
        case .assistant:
            return role?.capitalized ?? "Claude"
        case .summary:
            return "System"
        case .fileHistorySnapshot:
            return "System"
        }
    }

    var displayContent: String {
        if let raw = rawContent, type == .user {
            return raw
        }

        if !contentBlocks.isEmpty {
            // Find the first text or thinking block for display
            for block in contentBlocks {
                if block.type == .text, let text = block.text, !text.isEmpty {
                    return text
                }
            }
            // If no text, show tool use or thinking
            for block in contentBlocks {
                if block.type == .toolUse {
                    return block.displayContent
                }
                if block.type == .thinking, let thinking = block.thinking {
                    return "[Thinking] \(thinking.prefix(100))..."
                }
            }
        }

        return rawContent ?? ""
    }

    var contentSummary: String {
        let content = displayContent
        if content.count > 100 {
            return String(content.prefix(100)) + "..."
        }
        return content
    }

    /// Pure text content without tool invocation descriptions
    var pureTextContent: String {
        if let raw = rawContent, type == .user {
            return raw
        }

        // Collect only text blocks (not tool_use, thinking, or tool_result)
        let textParts = contentBlocks
            .filter { $0.type == .text }
            .compactMap { $0.text }
            .filter { !$0.isEmpty }

        return textParts.joined(separator: "\n")
    }

    /// Check if the message has no meaningful content
    var isEmpty: Bool {
        // For user messages, check rawContent
        if type == .user {
            return rawContent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        }

        // For other messages, check if there's any content
        let hasRawContent = !(rawContent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasContentBlocks = !contentBlocks.isEmpty

        return !hasRawContent && !hasContentBlocks
    }
}

// MARK: - Raw JSON Structures for Decoding
struct RawSessionEntry: Decodable {
    let type: String
    let uuid: String?
    let timestamp: String?
    let message: RawMessage?
    let summary: String?

    struct RawMessage: Decodable {
        let role: String?
        let content: RawContent?
        let model: String?
        let id: String?

        enum RawContent: Decodable {
            case string(String)
            case array([RawContentBlock])

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let str = try? container.decode(String.self) {
                    self = .string(str)
                } else if let arr = try? container.decode([RawContentBlock].self) {
                    self = .array(arr)
                } else {
                    self = .string("")
                }
            }
        }
    }

    struct RawContentBlock: Decodable {
        let type: String
        let text: String?
        let thinking: String?
        let name: String?
        let input: AnyCodable?
    }
}

// MARK: - AnyCodable for flexible JSON decoding
struct AnyCodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let str = try? container.decode(String.self) {
            value = str
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map { $0.value }
        } else {
            value = ""
        }
    }

    var stringValue: String {
        if let str = value as? String {
            return str
        }
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return String(describing: value)
    }
}
