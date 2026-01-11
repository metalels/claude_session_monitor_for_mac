import SwiftUI

struct ProjectListView: View {
    let projects: [Project]
    @Binding var selectedProject: Project?

    @State private var searchText = ""

    var filteredProjects: [Project] {
        if searchText.isEmpty {
            return projects
        }
        return projects.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Projects")
                    .font(.headline)
                Spacer()
                Text("\(projects.count)")
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
                TextField("Search projects...", text: $searchText)
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

            // Project list
            List(filteredProjects, selection: $selectedProject) { project in
                ProjectRowView(project: project)
                    .tag(project)
            }
            .listStyle(.sidebar)
        }
    }
}

struct ProjectRowView: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(projectName)
                .font(.system(.body, design: .default, weight: .medium))
                .lineLimit(2)

            Text(project.displayName)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private var projectName: String {
        // Extract the last component of the path as project name
        let components = project.displayName.split(separator: "/")
        return String(components.last ?? Substring(project.displayName))
    }
}

#Preview {
    ProjectListView(
        projects: [
            Project(directoryURL: URL(fileURLWithPath: "/Users/test/workspace/project1")),
            Project(directoryURL: URL(fileURLWithPath: "/Users/test/workspace/project2"))
        ],
        selectedProject: .constant(nil)
    )
    .frame(width: 200, height: 400)
}
