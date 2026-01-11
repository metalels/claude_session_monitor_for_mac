import Foundation

actor SessionParser {
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let fallbackDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    func parseFile(at url: URL) async throws -> [SessionMessage] {
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw ParserError.invalidEncoding
        }

        return parseLines(content)
    }

    func parseLines(_ content: String) -> [SessionMessage] {
        let lines = content.components(separatedBy: .newlines)
        return lines.compactMap { parseLine($0) }
    }

    func parseLine(_ line: String) -> SessionMessage? {
        guard !line.isEmpty else { return nil }

        guard let data = line.data(using: .utf8) else { return nil }

        do {
            let entry = try JSONDecoder().decode(RawSessionEntry.self, from: data)
            return convertToMessage(entry)
        } catch {
            // Silently ignore malformed lines
            return nil
        }
    }

    private func convertToMessage(_ entry: RawSessionEntry) -> SessionMessage? {
        guard let typeEnum = MessageType(rawValue: entry.type) else {
            return nil
        }

        let uuid = entry.uuid ?? UUID().uuidString
        let timestamp = parseDate(entry.timestamp)

        switch typeEnum {
        case .user:
            let content = extractUserContent(entry)
            return SessionMessage(
                id: uuid,
                type: .user,
                timestamp: timestamp,
                role: "user",
                model: nil,
                contentBlocks: [],
                rawContent: content
            )

        case .assistant:
            let (blocks, rawContent) = extractAssistantContent(entry)
            return SessionMessage(
                id: uuid,
                type: .assistant,
                timestamp: timestamp,
                role: "assistant",
                model: entry.message?.model,
                contentBlocks: blocks,
                rawContent: rawContent
            )

        case .summary:
            return SessionMessage(
                id: uuid,
                type: .summary,
                timestamp: timestamp,
                role: nil,
                model: nil,
                contentBlocks: [],
                rawContent: entry.summary
            )

        case .fileHistorySnapshot:
            return SessionMessage(
                id: uuid,
                type: .fileHistorySnapshot,
                timestamp: timestamp,
                role: nil,
                model: nil,
                contentBlocks: [],
                rawContent: "File history snapshot"
            )
        }
    }

    private func parseDate(_ dateString: String?) -> Date {
        guard let str = dateString else { return Date() }

        if let date = dateFormatter.date(from: str) {
            return date
        }
        if let date = fallbackDateFormatter.date(from: str) {
            return date
        }
        return Date()
    }

    private func extractUserContent(_ entry: RawSessionEntry) -> String {
        guard let message = entry.message, let content = message.content else {
            return ""
        }

        switch content {
        case .string(let str):
            return str
        case .array(let blocks):
            return blocks.compactMap { $0.text }.joined(separator: "\n")
        }
    }

    private func extractAssistantContent(_ entry: RawSessionEntry) -> ([ContentBlock], String?) {
        guard let message = entry.message, let content = message.content else {
            return ([], nil)
        }

        switch content {
        case .string(let str):
            return ([], str)

        case .array(let blocks):
            var contentBlocks: [ContentBlock] = []
            var textParts: [String] = []

            for block in blocks {
                let blockType = ContentBlockType(rawValue: block.type) ?? .text

                let contentBlock = ContentBlock(
                    type: blockType,
                    text: block.text,
                    thinking: block.thinking,
                    toolName: block.name,
                    toolInput: block.input?.stringValue
                )
                contentBlocks.append(contentBlock)

                if let text = block.text {
                    textParts.append(text)
                }
            }

            return (contentBlocks, textParts.isEmpty ? nil : textParts.joined(separator: "\n"))
        }
    }
}

enum ParserError: Error {
    case invalidEncoding
    case invalidJSON
}
