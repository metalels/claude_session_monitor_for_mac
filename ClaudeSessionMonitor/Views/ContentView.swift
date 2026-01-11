import SwiftUI

struct ContentView: View {
    @StateObject private var projectWatcher = ProjectDirectoryWatcher()
    @StateObject private var sessionWatcher = SessionDirectoryWatcher()
    @StateObject private var fileWatcher = SessionFileWatcher()

    @State private var selectedProject: Project?
    @State private var selectedSession: Session?
    @State private var showSettings = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    @AppStorage("showTypeColumn") private var showTypeColumn = true
    @AppStorage("showTimeColumn") private var showTimeColumn = true
    @AppStorage("showRoleColumn") private var showRoleColumn = true
    @AppStorage("showEmptyMessages") private var showEmptyMessages = false
    @AppStorage("rememberLastProject") private var rememberLastProject = true
    @AppStorage("lastProjectId") private var lastProjectId = ""

    var body: some View {
        NavigationSplitView(
            columnVisibility: $columnVisibility
        ) {
            // Left sidebar: Project list (1.5 ratio)
            ProjectListView(
                projects: projectWatcher.projects,
                selectedProject: $selectedProject
            )
            .navigationSplitViewColumnWidth(
                min: 150,
                ideal: Constants.SidebarWidths.projectList,
                max: 250
            )
        } content: {
            // Middle: Session list (1.5 ratio)
            SessionListView(
                sessions: sessionWatcher.sessions,
                selectedSession: $selectedSession
            )
            .navigationSplitViewColumnWidth(
                min: 150,
                ideal: Constants.SidebarWidths.sessionList,
                max: 250
            )
        } detail: {
            // Right: Session log (7 ratio)
            SessionLogView(
                messages: fileWatcher.messages,
                isWatching: fileWatcher.isWatching,
                showTypeColumn: showTypeColumn,
                showTimeColumn: showTimeColumn,
                showRoleColumn: showRoleColumn,
                showEmptyMessages: showEmptyMessages
            )
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gear")
                }
                .help("Settings")
            }

            ToolbarItem(placement: .automatic) {
                Button(action: {
                    Task {
                        await fileWatcher.reload()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload session")
                .disabled(selectedSession == nil)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                showTypeColumn: $showTypeColumn,
                showTimeColumn: $showTimeColumn,
                showRoleColumn: $showRoleColumn,
                showEmptyMessages: $showEmptyMessages,
                rememberLastProject: $rememberLastProject
            )
        }
        .onAppear {
            projectWatcher.startWatching()
        }
        .onChange(of: projectWatcher.projects) { _, projects in
            // Restore last project when projects are loaded
            if rememberLastProject && selectedProject == nil && !lastProjectId.isEmpty {
                if let project = projects.first(where: { $0.id == lastProjectId }) {
                    selectedProject = project
                }
            }
        }
        .onChange(of: selectedProject) { _, newProject in
            if let project = newProject {
                sessionWatcher.startWatching(project: project)
                selectedSession = nil

                // Save last project
                if rememberLastProject {
                    lastProjectId = project.id
                }
            }
        }
        .onChange(of: selectedSession) { _, newSession in
            if let session = newSession {
                Task {
                    await fileWatcher.startWatching(session: session)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

#Preview {
    ContentView()
}
