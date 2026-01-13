import Foundation
import Combine

@MainActor
class SessionFileWatcher: ObservableObject {
    private var fileHandle: FileHandle?
    private var source: DispatchSourceFileSystemObject?
    private var lastReadPosition: UInt64 = 0
    private let parser = SessionParser()

    @Published var messages: [SessionMessage] = []
    @Published var isWatching = false

    private var currentFilePath: URL?

    func startWatching(session: Session) async {
        await stopWatching()

        currentFilePath = session.filePath

        // Initial load of all existing content
        do {
            let existingMessages = try await parser.parseFile(at: session.filePath)
            self.messages = existingMessages
        } catch {
            print("Error loading session file: \(error)")
            self.messages = []
        }

        // Start watching for changes
        startFileMonitor(at: session.filePath)
    }

    func stopWatching() async {
        source?.cancel()
        source = nil

        try? fileHandle?.close()
        fileHandle = nil

        lastReadPosition = 0
        isWatching = false
    }

    private func startFileMonitor(at url: URL) {
        guard let handle = FileHandle(forReadingAtPath: url.path) else {
            print("Cannot open file for monitoring: \(url.path)")
            return
        }

        fileHandle = handle

        // Move to end of file
        handle.seekToEndOfFile()
        lastReadPosition = handle.offsetInFile

        let fd = handle.fileDescriptor
        let queue = DispatchQueue(label: "com.claudesessionmonitor.filewatcher")

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.extend, .write],
            queue: queue
        )

        source?.setEventHandler { [weak self] in
            self?.handleFileChange()
        }

        source?.setCancelHandler { [weak self] in
            try? self?.fileHandle?.close()
        }

        source?.resume()
        isWatching = true
    }

    private func handleFileChange() {
        guard let handle = fileHandle else { return }

        // Read new content from last position
        handle.seek(toFileOffset: lastReadPosition)
        let newData = handle.readDataToEndOfFile()
        lastReadPosition = handle.offsetInFile

        guard !newData.isEmpty,
              let newContent = String(data: newData, encoding: .utf8) else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let newMessages = await self.parser.parseLines(newContent)

            if !newMessages.isEmpty {
                self.messages.append(contentsOf: newMessages)
            }
        }
    }

    func reload() async {
        guard let path = currentFilePath else { return }

        do {
            let allMessages = try await parser.parseFile(at: path)
            self.messages = allMessages
        } catch {
            print("Error reloading session: \(error)")
        }
    }
}

// MARK: - Recent Sessions Watcher
@MainActor
class RecentSessionsWatcher: ObservableObject {
    private var sources: [DispatchSourceFileSystemObject] = []
    private var fileDescriptors: [Int32] = []
    private let parser = SessionParser()

    @Published var sessions: [Session] = []

    private var initialSessionIds: Set<UUID> = []
    private var hasInitialized = false

    func startWatching() {
        stopWatching()
        loadRecentSessions()
        startAllProjectsMonitoring()
    }

    func stopWatching() {
        for source in sources {
            source.cancel()
        }
        sources.removeAll()

        for fd in fileDescriptors {
            if fd >= 0 {
                close(fd)
            }
        }
        fileDescriptors.removeAll()
    }

    private func loadRecentSessions() {
        let projectsPath = Constants.claudeProjectsPath

        guard FileManager.default.fileExists(atPath: projectsPath.path) else {
            sessions = []
            return
        }

        do {
            let projectDirs = try FileManager.default.contentsOfDirectory(
                at: projectsPath,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ).filter { url in
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                return isDirectory.boolValue
            }

            var allSessions: [Session] = []

            for projectDir in projectDirs {
                let projectId = projectDir.lastPathComponent
                let jsonlFiles = try FileManager.default.contentsOfDirectory(
                    at: projectDir,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                ).filter { $0.pathExtension == "jsonl" }

                for file in jsonlFiles {
                    var session = Session(filePath: file, projectId: projectId)
                    if let summary = loadSessionSummary(from: file) {
                        session.summary = summary
                    }
                    allSessions.append(session)
                }
            }

            // Sort by last modified and take top 10
            let sortedSessions = allSessions.sorted { $0.lastModified > $1.lastModified }
            let topSessions = Array(sortedSessions.prefix(10))

            if !hasInitialized {
                // First load: store initial session IDs
                initialSessionIds = Set(topSessions.map { $0.id })
                hasInitialized = true
                sessions = topSessions
            } else {
                // Subsequent updates: merge with existing sessions
                // New sessions go to top, existing ones stay in their positions
                let existingIds = Set(sessions.map { $0.id })
                let newSessions = sortedSessions.filter { !existingIds.contains($0.id) }

                if !newSessions.isEmpty {
                    // Insert new sessions at the top
                    sessions = newSessions + sessions
                }

                // Update modification times for existing sessions
                for (index, existingSession) in sessions.enumerated() {
                    if let updated = sortedSessions.first(where: { $0.id == existingSession.id }) {
                        sessions[index].lastModified = updated.lastModified
                        sessions[index].summary = updated.summary
                    }
                }
            }

        } catch {
            print("Error loading recent sessions: \(error)")
        }
    }

    private func loadSessionSummary(from url: URL) -> String? {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return nil }
        defer { try? handle.close() }

        let data = handle.readData(ofLength: 4096)
        guard let content = String(data: data, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: .newlines)

        for line in lines.prefix(10) {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String,
                  type == "summary",
                  let summary = json["summary"] as? String else {
                continue
            }
            return summary
        }

        return nil
    }

    private func startAllProjectsMonitoring() {
        let projectsPath = Constants.claudeProjectsPath

        guard FileManager.default.fileExists(atPath: projectsPath.path) else { return }

        do {
            let projectDirs = try FileManager.default.contentsOfDirectory(
                at: projectsPath,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ).filter { url in
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                return isDirectory.boolValue
            }

            for projectDir in projectDirs {
                startDirectoryMonitor(at: projectDir)
            }

            // Also watch the main projects directory for new projects
            startDirectoryMonitor(at: projectsPath)

        } catch {
            print("Error setting up project monitoring: \(error)")
        }
    }

    private func startDirectoryMonitor(at url: URL) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        fileDescriptors.append(fd)

        let queue = DispatchQueue(label: "com.claudesessionmonitor.recentwatcher.\(url.lastPathComponent)")

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .link],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.loadRecentSessions()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        sources.append(source)
    }

    func reset() {
        hasInitialized = false
        initialSessionIds.removeAll()
        sessions.removeAll()
    }
}

// MARK: - Project Directory Watcher
@MainActor
class ProjectDirectoryWatcher: ObservableObject {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    @Published var projects: [Project] = []

    func startWatching() {
        loadProjects()
        startDirectoryMonitor()
    }

    func stopWatching() {
        source?.cancel()
        source = nil

        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    private func loadProjects() {
        let projectsPath = Constants.claudeProjectsPath

        guard FileManager.default.fileExists(atPath: projectsPath.path) else {
            projects = []
            return
        }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: projectsPath,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            let projectDirs = contents.filter { url in
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                return isDirectory.boolValue
            }

            projects = projectDirs
                .map { Project(directoryURL: $0) }
                .sorted { $0.displayName < $1.displayName }

        } catch {
            print("Error loading projects: \(error)")
            projects = []
        }
    }

    private func startDirectoryMonitor() {
        let path = Constants.claudeProjectsPath.path

        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("Cannot open directory for monitoring: \(path)")
            return
        }

        let queue = DispatchQueue(label: "com.claudesessionmonitor.dirwatcher")

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .link],
            queue: queue
        )

        source?.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.loadProjects()
            }
        }

        source?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
            }
        }

        source?.resume()
    }
}

// MARK: - Session Directory Watcher
@MainActor
class SessionDirectoryWatcher: ObservableObject {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let parser = SessionParser()

    @Published var sessions: [Session] = []

    private var currentProject: Project?

    func startWatching(project: Project) {
        stopWatching()
        currentProject = project
        loadSessions(from: project)
        startDirectoryMonitor(at: project.path)
    }

    func stopWatching() {
        source?.cancel()
        source = nil

        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    private func loadSessions(from project: Project) {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: project.path,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            let jsonlFiles = contents.filter { $0.pathExtension == "jsonl" }

            var loadedSessions: [Session] = []

            for file in jsonlFiles {
                var session = Session(filePath: file, projectId: project.id)

                // Try to load summary from first few lines
                if let summary = loadSessionSummary(from: file) {
                    session.summary = summary
                }

                loadedSessions.append(session)
            }

            sessions = loadedSessions.sorted { $0.lastModified > $1.lastModified }

        } catch {
            print("Error loading sessions: \(error)")
            sessions = []
        }
    }

    private func loadSessionSummary(from url: URL) -> String? {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return nil }
        defer { try? handle.close() }

        // Read first few KB to find summary
        let data = handle.readData(ofLength: 4096)
        guard let content = String(data: data, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: .newlines)

        for line in lines.prefix(10) {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String,
                  type == "summary",
                  let summary = json["summary"] as? String else {
                continue
            }
            return summary
        }

        return nil
    }

    private func startDirectoryMonitor(at url: URL) {
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("Cannot open directory for monitoring: \(url.path)")
            return
        }

        let queue = DispatchQueue(label: "com.claudesessionmonitor.sessionwatcher")

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .link],
            queue: queue
        )

        source?.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, let project = self.currentProject else { return }
                self.loadSessions(from: project)
            }
        }

        source?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
            }
        }

        source?.resume()
    }
}
