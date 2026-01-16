import SwiftUI

struct SessionListView: View {
    let sessions: [Session]
    @Binding var selectedSession: Session?

    @State private var searchText = ""

    var filteredSessions: [Session] {
        if searchText.isEmpty {
            return sessions
        }
        return sessions.filter {
            $0.summary?.localizedCaseInsensitiveContains(searchText) == true ||
            $0.id.uuidString.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Sessions")
                    .font(.headline)
                Spacer()
                Text("\(sessions.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search sessions...", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            if sessions.isEmpty {
                VStack {
                    Spacer()
                    Text("No sessions")
                        .foregroundColor(.secondary)
                    Text("Select a project first")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(filteredSessions, selection: $selectedSession) { session in
                    SessionRowView(session: session, isSelected: selectedSession?.id == session.id)
                        .tag(session)
                }
                .listStyle(.inset)
            }
        }
    }
}

struct SessionRowView: View {
    let session: Session
    let isSelected: Bool

    @State private var showCopiedFeedback = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Date and time
            HStack {
                Text(dateString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)

                // Copy path button
                Button(action: copyFilePath) {
                    Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundColor(showCopiedFeedback ? .green : (isSelected ? .white.opacity(0.7) : .secondary))
                }
                .buttonStyle(.plain)
                .help("Copy session file path")

                Spacer()

                // Message count badge
                if session.messageCount > 0 {
                    Text("\(session.messageCount)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.white.opacity(0.3) : Color.accentColor.opacity(0.2))
                        .cornerRadius(4)
                }
            }

            // Summary or UUID
            if let summary = session.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(.body))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(2)
            } else {
                Text(session.id.uuidString.prefix(8) + "...")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor : Color.clear)
        .cornerRadius(6)
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: session.lastModified)
    }

    private func copyFilePath() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(session.filePath.path, forType: .string)

        // Show feedback
        withAnimation {
            showCopiedFeedback = true
        }

        // Reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopiedFeedback = false
            }
        }
    }
}

#Preview {
    SessionListView(
        sessions: [],
        selectedSession: .constant(nil)
    )
    .frame(width: 200, height: 400)
}
