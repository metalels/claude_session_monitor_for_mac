import SwiftUI

struct SessionLogView: View {
    let messages: [SessionMessage]
    let isWatching: Bool
    let showTypeColumn: Bool
    let showTimeColumn: Bool
    let showRoleColumn: Bool
    let showEmptyMessages: Bool

    @State private var selectedTypes: Set<MessageType> = Set(MessageType.allCases)
    @State private var selectedTools: Set<String> = []
    @State private var allTools: [String] = []
    @State private var showAllTools = true
    @State private var searchText = ""
    @State private var autoScroll = true
    @State private var selectedMessage: SessionMessage?

    var filteredMessages: [SessionMessage] {
        messages.filter { message in
            // Filter by type
            guard selectedTypes.contains(message.type) else { return false }

            // Filter empty messages
            if !showEmptyMessages && message.isEmpty {
                return false
            }

            // Filter by tool (if tool filter is active)
            if !showAllTools && !selectedTools.isEmpty {
                let messageTools = message.contentBlocks
                    .filter { $0.type == .toolUse }
                    .compactMap { $0.toolName }

                if !messageTools.isEmpty {
                    // If message has tools, check if any match the filter
                    let hasMatchingTool = messageTools.contains { selectedTools.contains($0) }
                    if !hasMatchingTool { return false }
                }
            }

            // Filter by search text
            if !searchText.isEmpty {
                let content = message.displayContent.lowercased()
                let role = message.displayRole.lowercased()
                let search = searchText.lowercased()
                return content.contains(search) || role.contains(search)
            }

            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with filters
            FilterBarView(
                selectedTypes: $selectedTypes,
                selectedTools: $selectedTools,
                allTools: allTools,
                showAllTools: $showAllTools,
                searchText: $searchText,
                autoScroll: $autoScroll,
                messageCount: messages.count,
                filteredCount: filteredMessages.count,
                isWatching: isWatching
            )

            Divider()

            // Message table
            if messages.isEmpty {
                EmptyStateView()
            } else {
                MessageTableView(
                    messages: filteredMessages,
                    selectedMessage: $selectedMessage,
                    showTypeColumn: showTypeColumn,
                    showTimeColumn: showTimeColumn,
                    showRoleColumn: showRoleColumn,
                    autoScroll: autoScroll
                )
            }
        }
        .onChange(of: messages.count) { _, _ in
            updateToolList(from: messages)
        }
        .onAppear {
            updateToolList(from: messages)
        }
    }

    private func updateToolList(from messages: [SessionMessage]) {
        var tools = Set<String>()
        for message in messages {
            for block in message.contentBlocks where block.type == .toolUse {
                if let toolName = block.toolName {
                    tools.insert(toolName)
                }
            }
        }
        allTools = tools.sorted()
    }
}

// MARK: - Filter Bar
struct FilterBarView: View {
    @Binding var selectedTypes: Set<MessageType>
    @Binding var selectedTools: Set<String>
    let allTools: [String]
    @Binding var showAllTools: Bool
    @Binding var searchText: String
    @Binding var autoScroll: Bool
    let messageCount: Int
    let filteredCount: Int
    let isWatching: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Type filter
            Menu {
                ForEach(MessageType.allCases, id: \.self) { type in
                    Button(action: { toggleType(type) }) {
                        HStack {
                            if selectedTypes.contains(type) {
                                Image(systemName: "checkmark")
                            }
                            Text(type.displayName)
                        }
                    }
                }

                Divider()

                Button("Select All") {
                    selectedTypes = Set(MessageType.allCases)
                }
                Button("Clear All") {
                    selectedTypes = []
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text("Type")
                    if selectedTypes.count < MessageType.allCases.count {
                        Text("(\(selectedTypes.count))")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Tool filter
            Menu {
                Toggle("Show All Tools", isOn: $showAllTools)
                    .onChange(of: showAllTools) { _, newValue in
                        if newValue {
                            selectedTools = []
                        }
                    }

                Divider()

                ForEach(allTools, id: \.self) { tool in
                    Button(action: {
                        showAllTools = false
                        toggleTool(tool)
                    }) {
                        HStack {
                            if selectedTools.contains(tool) {
                                Image(systemName: "checkmark")
                            }
                            Text(tool)
                        }
                    }
                }

                if !allTools.isEmpty {
                    Divider()

                    Button("Select All Tools") {
                        showAllTools = false
                        selectedTools = Set(allTools)
                    }
                    Button("Clear Tool Filter") {
                        showAllTools = true
                        selectedTools = []
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "terminal")
                    Text("Tools")
                    if !showAllTools && !selectedTools.isEmpty {
                        Text("(\(selectedTools.count))")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search in messages...", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .frame(maxWidth: 300)

            Spacer()

            // Message count
            HStack(spacing: 4) {
                if messageCount != filteredCount {
                    Text("\(filteredCount) / \(messageCount)")
                } else {
                    Text("\(messageCount)")
                }
                Text("messages")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            // Live indicator
            if isWatching {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Live")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            // Auto-scroll toggle
            Toggle(isOn: $autoScroll) {
                Image(systemName: "arrow.down.to.line")
            }
            .toggleStyle(.button)
            .help("Auto-scroll to bottom")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func toggleType(_ type: MessageType) {
        if selectedTypes.contains(type) {
            selectedTypes.remove(type)
        } else {
            selectedTypes.insert(type)
        }
    }

    private func toggleTool(_ tool: String) {
        if selectedTools.contains(tool) {
            selectedTools.remove(tool)
        } else {
            selectedTools.insert(tool)
        }
    }
}

// MARK: - Empty State
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No session selected")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Select a project and session to view logs")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Message Table
struct MessageTableView: View {
    let messages: [SessionMessage]
    @Binding var selectedMessage: SessionMessage?
    let showTypeColumn: Bool
    let showTimeColumn: Bool
    let showRoleColumn: Bool
    let autoScroll: Bool

    var body: some View {
        ScrollViewReader { proxy in
            List(messages) { message in
                MessageRowView(
                    message: message,
                    showTypeColumn: showTypeColumn,
                    showTimeColumn: showTimeColumn,
                    showRoleColumn: showRoleColumn
                )
                .id(message.id)
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            }
            .listStyle(.plain)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // 5行分程度の空白エリアを追加してスクロールしやすくする
                Color.clear.frame(height: 120)
            }
            .onAppear {
                // Scroll to last message when session is opened
                if let lastMessage = messages.last {
                    // Multiple delayed scrolls to handle dynamic content rendering
                    for delay in [0.1, 0.3, 0.5] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            .onChange(of: messages.count) { _, _ in
                if autoScroll, let lastMessage = messages.last {
                    // Multiple delayed scrolls to handle dynamic content height
                    for delay in [0.05, 0.2, 0.4] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Message Row
struct MessageRowView: View {
    let message: SessionMessage
    let showTypeColumn: Bool
    let showTimeColumn: Bool
    let showRoleColumn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row with metadata
            HStack(alignment: .center, spacing: 8) {
                if showTypeColumn {
                    TypeBadge(type: message.type)
                }

                if showTimeColumn {
                    Text(message.displayTime)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                if showRoleColumn {
                    RoleBadge(role: message.displayRole)
                }

                Spacer()
            }

            // Content - always show full content
            MessageContentView(message: message)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .cornerRadius(8)
    }
}

// MARK: - Message Content View (Full content display)
struct MessageContentView: View {
    let message: SessionMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // For User messages, show rawContent
            if message.type == .user {
                if let rawContent = message.rawContent, !rawContent.isEmpty {
                    MarkdownText(rawContent)
                } else {
                    Text("(empty message)")
                        .font(.system(.body))
                        .foregroundColor(.secondary)
                        .italic()
                }
            } else {
                // Show text content
                let textContent = message.pureTextContent
                if !textContent.isEmpty {
                    MarkdownText(textContent)
                }

                // Show tools in human-readable format
                let toolBlocks = message.contentBlocks.filter { $0.type == .toolUse }
                ForEach(toolBlocks) { block in
                    CompactToolView(block: block)
                }

                // Show thinking
                let thinkingBlocks = message.contentBlocks.filter { $0.type == .thinking }
                ForEach(thinkingBlocks) { block in
                    ThinkingBlockView(block: block)
                }

                // Show tool results
                let resultBlocks = message.contentBlocks.filter { $0.type == .toolResult }
                ForEach(resultBlocks) { block in
                    ToolResultBlockView(block: block)
                }
            }
        }
    }
}

// MARK: - Collapsed Content View
struct CollapsedContentView: View {
    let message: SessionMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // For User messages, always show rawContent
            if message.type == .user {
                if let rawContent = message.rawContent, !rawContent.isEmpty {
                    MarkdownText(rawContent)
                        .lineLimit(5)
                } else {
                    Text("(empty message)")
                        .font(.system(.body))
                        .foregroundColor(.secondary)
                        .italic()
                }
            } else {
                // Show text content if it's not just tool invocation description
                let textContent = message.pureTextContent
                if !textContent.isEmpty {
                    MarkdownText(textContent)
                        .lineLimit(3)
                }

                // Show tools in human-readable format
                let toolBlocks = message.contentBlocks.filter { $0.type == .toolUse }
                ForEach(toolBlocks) { block in
                    CompactToolView(block: block)
                }

                // Show thinking summary
                let thinkingBlocks = message.contentBlocks.filter { $0.type == .thinking }
                if !thinkingBlocks.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "brain.head.profile")
                            .font(.caption)
                            .foregroundColor(.purple)
                        Text("Thinking...")
                            .font(.caption)
                            .foregroundColor(.purple)
                    }
                }
            }
        }
    }
}

// MARK: - Markdown Text View
struct MarkdownText: View {
    let text: String
    var lineLimit: Int? = nil

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed)
                .font(.system(.body))
                .textSelection(.enabled)
                .lineLimit(lineLimit)
        } else {
            Text(text)
                .font(.system(.body))
                .textSelection(.enabled)
                .lineLimit(lineLimit)
        }
    }

    func lineLimit(_ limit: Int?) -> MarkdownText {
        var copy = self
        copy.lineLimit = limit
        return copy
    }
}

// MARK: - Compact Tool View (Human-readable, always expanded)
struct CompactToolView: View {
    let block: ContentBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Tool header with badge
            HStack(spacing: 6) {
                Image(systemName: iconForTool(block.toolName ?? ""))
                    .font(.caption)
                    .foregroundColor(.orange)
                Text(block.toolName ?? "Tool")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundColor(.orange)
            }

            // Tool parameters in human-readable format
            if let input = block.toolInput {
                CompactToolInputView(toolName: block.toolName ?? "", input: input)
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }

    private func iconForTool(_ name: String) -> String {
        switch name.lowercased() {
        case "bash": return "terminal"
        case "read": return "doc.text"
        case "write": return "square.and.pencil"
        case "edit": return "pencil"
        case "glob": return "folder.badge.questionmark"
        case "grep": return "magnifyingglass"
        case "webfetch": return "globe"
        case "websearch": return "magnifyingglass"
        case "task": return "checklist"
        case "todowrite": return "checklist"
        default: return "terminal"
        }
    }
}

// MARK: - Compact Tool Input View
struct CompactToolInputView: View {
    let toolName: String
    let input: String

    var body: some View {
        if let (simpleParams, arrayParams) = parseInputSeparated() {
            VStack(alignment: .leading, spacing: 6) {
                // Show simple parameters first
                ForEach(sortedKeys(simpleParams), id: \.self) { key in
                    if let value = simpleParams[key] {
                        CompactParameterRow(key: key, value: value, toolName: toolName)
                    }
                }

                // Show array parameters with better formatting
                ForEach(Array(arrayParams.keys.sorted()), id: \.self) { key in
                    if let items = arrayParams[key] {
                        ArrayParameterView(key: key, items: items, toolName: toolName)
                    }
                }
            }
        } else {
            // Fallback: show truncated raw input
            Text(input.prefix(150) + (input.count > 150 ? "..." : ""))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    private func sortedKeys(_ dict: [String: String]) -> [String] {
        let priority = ["command", "file_path", "path", "pattern", "query", "content", "description"]
        return dict.keys.sorted { key1, key2 in
            let idx1 = priority.firstIndex(of: key1) ?? 999
            let idx2 = priority.firstIndex(of: key2) ?? 999
            if idx1 != idx2 { return idx1 < idx2 }
            return key1 < key2
        }
    }

    private func parseInputSeparated() -> ([String: String], [String: [[String: Any]]])? {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var simpleParams: [String: String] = [:]
        var arrayParams: [String: [[String: Any]]] = [:]

        for (key, value) in json {
            if let stringValue = value as? String {
                simpleParams[key] = stringValue
            } else if let boolValue = value as? Bool {
                simpleParams[key] = boolValue ? "true" : "false"
            } else if let numberValue = value as? NSNumber {
                simpleParams[key] = numberValue.stringValue
            } else if let arrayValue = value as? [[String: Any]] {
                // Array of objects (like todos)
                arrayParams[key] = arrayValue
            } else if let arrayValue = value as? [Any] {
                // Simple array - convert to string
                if let jsonData = try? JSONSerialization.data(withJSONObject: arrayValue, options: []),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    simpleParams[key] = jsonString
                }
            } else if let dictValue = value as? [String: Any] {
                if let jsonData = try? JSONSerialization.data(withJSONObject: dictValue, options: []),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    simpleParams[key] = jsonString
                }
            }
        }
        return (simpleParams, arrayParams)
    }
}

// MARK: - Array Parameter View (for todos, etc.)
struct ArrayParameterView: View {
    let key: String
    let items: [[String: Any]]
    let toolName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formatKey(key) + " (\(items.count) items)")
                .font(.caption)
                .foregroundColor(.secondary)
                .fontWeight(.medium)

            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                ArrayItemView(index: index, item: item, toolName: toolName)
            }
        }
    }

    private func formatKey(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - Array Item View (single todo item, etc.)
struct ArrayItemView: View {
    let index: Int
    let item: [String: Any]
    let toolName: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Index badge
            Text("\(index + 1)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(statusColor)
                .cornerRadius(9)

            // Item content
            VStack(alignment: .leading, spacing: 2) {
                // For TodoWrite, show content prominently
                if let content = item["content"] as? String {
                    Text(content)
                        .font(.caption)
                        .fontWeight(.medium)
                }

                // Show other fields
                HStack(spacing: 8) {
                    if let status = item["status"] as? String {
                        StatusBadge(status: status)
                    }
                    if let activeForm = item["activeForm"] as? String {
                        Text(activeForm)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(4)
    }

    private var statusColor: Color {
        if let status = item["status"] as? String {
            switch status {
            case "completed": return .green
            case "in_progress": return .blue
            case "pending": return .gray
            default: return .gray
            }
        }
        return .gray
    }
}

// MARK: - Status Badge
struct StatusBadge: View {
    let status: String

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: iconName)
                .font(.caption2)
            Text(displayName)
                .font(.caption2)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(backgroundColor)
        .foregroundColor(foregroundColor)
        .cornerRadius(3)
    }

    private var iconName: String {
        switch status {
        case "completed": return "checkmark.circle.fill"
        case "in_progress": return "play.circle.fill"
        case "pending": return "circle"
        default: return "circle"
        }
    }

    private var displayName: String {
        switch status {
        case "completed": return "Done"
        case "in_progress": return "Active"
        case "pending": return "Pending"
        default: return status
        }
    }

    private var backgroundColor: Color {
        switch status {
        case "completed": return .green.opacity(0.2)
        case "in_progress": return .blue.opacity(0.2)
        case "pending": return .gray.opacity(0.2)
        default: return .gray.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch status {
        case "completed": return .green
        case "in_progress": return .blue
        case "pending": return .gray
        default: return .gray
        }
    }
}

// MARK: - Compact Parameter Row
struct CompactParameterRow: View {
    let key: String
    let value: String
    let toolName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Parameter label
            HStack(spacing: 4) {
                Image(systemName: iconForKey(key))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(formatKey(key))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }

            // Parameter value - show full content for Edit tool's strings
            if shouldShowFullContent {
                ScrollView {
                    Text(value)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
                .padding(6)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(4)
            } else if isCodeContent(key) || value.count > 80 {
                Text(value.prefix(200) + (value.count > 200 ? "..." : ""))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(3)
            } else {
                Text(value)
                    .font(.caption)
                    .textSelection(.enabled)
            }
        }
    }

    private var shouldShowFullContent: Bool {
        // Always show full content for these tool parameters
        let tool = toolName.lowercased()
        let k = key.lowercased()

        // Edit tool: old_string, new_string
        if tool == "edit" && ["old_string", "new_string"].contains(k) {
            return true
        }

        // Bash tool: command
        if tool == "bash" && k == "command" {
            return true
        }

        // Read tool: file_path (short, but consistent)
        if tool == "read" && k == "file_path" {
            return true
        }

        // Write tool: content, file_path
        if tool == "write" && ["content", "file_path"].contains(k) {
            return true
        }

        // Grep tool: pattern, path
        if tool == "grep" && ["pattern", "path"].contains(k) {
            return true
        }

        // Glob tool: pattern, path
        if tool == "glob" && ["pattern", "path"].contains(k) {
            return true
        }

        return false
    }

    private func iconForKey(_ key: String) -> String {
        switch key.lowercased() {
        case "command": return "terminal"
        case "file_path", "path", "filename": return "doc"
        case "content", "text": return "text.alignleft"
        case "pattern": return "magnifyingglass"
        case "description": return "text.quote"
        case "url": return "link"
        case "query": return "magnifyingglass"
        case "old_string": return "minus.circle"
        case "new_string": return "plus.circle"
        case "replace_all": return "arrow.triangle.2.circlepath"
        default: return "circle.fill"
        }
    }

    private func formatKey(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func isCodeContent(_ key: String) -> Bool {
        ["command", "content", "code", "script", "pattern"].contains(key.lowercased())
    }
}

// MARK: - Expanded Content View
struct ExpandedContentView: View {
    let message: SessionMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Full text content
            if !message.displayContent.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Message")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    MarkdownText(message.displayContent)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
            }

            // Content blocks (tools, thinking, etc.)
            ForEach(message.contentBlocks) { block in
                ContentBlockView(block: block)
            }
        }
    }
}

// MARK: - Content Block View
struct ContentBlockView: View {
    let block: ContentBlock

    var body: some View {
        switch block.type {
        case .toolUse:
            ToolUseBlockView(block: block)
        case .thinking:
            ThinkingBlockView(block: block)
        case .toolResult:
            ToolResultBlockView(block: block)
        case .text:
            if let text = block.text, !text.isEmpty {
                TextBlockView(text: text)
            }
        }
    }
}

// MARK: - Tool Use Block View
struct ToolUseBlockView: View {
    let block: ContentBlock
    @State private var isInputExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: isInputExpanded ? 8 : 6) {
            // Tool header - entire row is tappable
            HStack {
                Image(systemName: "terminal.fill")
                    .foregroundColor(.orange)
                Text(block.toolName ?? "Tool")
                    .font(.headline)
                    .foregroundColor(.orange)

                Spacer()

                Image(systemName: isInputExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14, weight: .medium))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isInputExpanded.toggle()
                }
            }

            // Tool input (parsed nicely)
            if isInputExpanded, let input = block.toolInput {
                ToolInputView(toolName: block.toolName ?? "", input: input)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let input = block.toolInput {
                // Preview of input
                Text(input.prefix(100) + (input.count > 100 ? "..." : ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Tool Input View (Human-readable format)
struct ToolInputView: View {
    let toolName: String
    let input: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Parse and display based on tool type
            if let parsed = parseInput() {
                ForEach(Array(parsed.keys.sorted()), id: \.self) { key in
                    if let value = parsed[key] {
                        ToolParameterRow(key: key, value: value, toolName: toolName)
                    }
                }
            } else {
                // Fallback: show raw input
                Text(input)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(4)
            }
        }
    }

    private func parseInput() -> [String: String]? {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var result: [String: String] = [:]
        for (key, value) in json {
            if let stringValue = value as? String {
                result[key] = stringValue
            } else if let boolValue = value as? Bool {
                result[key] = boolValue ? "true" : "false"
            } else if let numberValue = value as? NSNumber {
                result[key] = numberValue.stringValue
            } else if let arrayValue = value as? [Any] {
                if let jsonData = try? JSONSerialization.data(withJSONObject: arrayValue, options: .prettyPrinted),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    result[key] = jsonString
                }
            } else if let dictValue = value as? [String: Any] {
                if let jsonData = try? JSONSerialization.data(withJSONObject: dictValue, options: .prettyPrinted),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    result[key] = jsonString
                }
            }
        }
        return result.isEmpty ? nil : result
    }
}

// MARK: - Tool Parameter Row
struct ToolParameterRow: View {
    let key: String
    let value: String
    let toolName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Parameter name with icon
            HStack(spacing: 4) {
                Image(systemName: iconForKey(key))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(formatKey(key))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }

            // Parameter value
            if isCodeContent(key) {
                // Show as code block
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(value)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(4)
            } else if value.count > 200 {
                // Truncate long values with expand option
                ExpandableText(text: value)
            } else {
                Text(value)
                    .font(.system(.body))
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }

    private func iconForKey(_ key: String) -> String {
        switch key.lowercased() {
        case "command": return "terminal"
        case "file_path", "path", "filename": return "doc"
        case "content", "text": return "text.alignleft"
        case "pattern": return "magnifyingglass"
        case "description": return "text.quote"
        case "url": return "link"
        case "query": return "magnifyingglass"
        default: return "circle.fill"
        }
    }

    private func formatKey(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func isCodeContent(_ key: String) -> Bool {
        ["command", "content", "code", "script", "query"].contains(key.lowercased())
    }
}

// MARK: - Expandable Text
struct ExpandableText: View {
    let text: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isExpanded ? text : String(text.prefix(200)) + "...")
                .font(.system(.body))
                .textSelection(.enabled)

            Button(action: { isExpanded.toggle() }) {
                Text(isExpanded ? "Show less" : "Show more")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Thinking Block View
struct ThinkingBlockView: View {
    let block: ContentBlock
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 8 : 0) {
            // Header - entire row is tappable
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.purple)
                Text("Thinking")
                    .font(.headline)
                    .foregroundColor(.purple)

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14, weight: .medium))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }

            // Content
            if isExpanded, let thinking = block.thinking {
                Text(thinking)
                    .font(.system(.caption))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(Color.purple.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Tool Result Block View
struct ToolResultBlockView: View {
    let block: ContentBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundColor(.green)
                Text("Result")
                    .font(.headline)
                    .foregroundColor(.green)
            }

            if let text = block.text {
                ScrollView {
                    Text(text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(4)
            }
        }
        .padding(10)
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Text Block View
struct TextBlockView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.body))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Tool Badge
struct ToolBadge: View {
    let toolName: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "terminal")
                .font(.caption2)
            Text(toolName)
                .font(.caption)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.2))
        .foregroundColor(.orange)
        .cornerRadius(4)
    }
}

// MARK: - Badges
struct TypeBadge: View {
    let type: MessageType

    var body: some View {
        Text(type.displayName)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(4)
    }

    private var backgroundColor: Color {
        switch type {
        case .user: return Color.blue.opacity(0.2)
        case .assistant: return Color.purple.opacity(0.2)
        case .summary: return Color.gray.opacity(0.2)
        case .fileHistorySnapshot: return Color.orange.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch type {
        case .user: return .blue
        case .assistant: return .purple
        case .summary: return .gray
        case .fileHistorySnapshot: return .orange
        }
    }
}

struct RoleBadge: View {
    let role: String

    var body: some View {
        Text(role)
            .font(.caption)
            .foregroundColor(roleColor)
    }

    private var roleColor: Color {
        switch role.lowercased() {
        case "user": return .blue
        case "claude", "assistant": return .purple
        case "system": return .gray
        default: return .primary
        }
    }
}

#Preview {
    SessionLogView(
        messages: [],
        isWatching: false,
        showTypeColumn: true,
        showTimeColumn: true,
        showRoleColumn: true,
        showEmptyMessages: false
    )
    .frame(width: 700, height: 500)
}
