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
    private var sourcePathMap: [ObjectIdentifier: String] = [:]  // Map source to path for cleanup
    private var monitoredPaths: Set<String> = []  // Track monitored directories
    private let parser = SessionParser()
    private var reloadTask: Task<Void, Never>?
    private var ioTask: Task<([Session], Set<String>)?, Never>?

    @Published var sessions: [Session] = []

    func startWatching() {
        stopWatching()
        // Start monitoring parent directory first (for detecting new projects)
        startDirectoryMonitor(at: Constants.claudeProjectsPath)
        // Then trigger reload which will also add monitors for existing projects
        triggerReload()
    }

    func stopWatching() {
        reloadTask?.cancel()
        reloadTask = nil
        ioTask?.cancel()
        ioTask = nil

        for source in sources {
            source.cancel()
        }
        sources.removeAll()
        sourcePathMap.removeAll()
        monitoredPaths.removeAll()
        // Note: FDs are closed by setCancelHandler, no manual close needed
    }

    /// Triggers background reload of recent sessions with debounce
    /// Also checks for new/removed project directories to update monitors
    private func triggerReload() {
        reloadTask?.cancel()
        ioTask?.cancel()
        reloadTask = Task { [weak self] in
            // Debounce: wait 0.5 seconds before loading
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }

            // Run I/O in detached task (off MainActor) for better performance
            let detachedTask = Task.detached {
                await Self.loadRecentSessionsAndProjectPaths()
            }
            self?.ioTask = detachedTask

            // Use withTaskCancellationHandler to cancel detached task when parent is cancelled
            let result = await withTaskCancellationHandler {
                await detachedTask.value
            } onCancel: {
                detachedTask.cancel()
            }

            guard !Task.isCancelled else { return }

            // Only update if we got valid results (nil means error - keep existing data)
            if let (loadedSessions, currentProjectPaths) = result {
                self?.updateSessions(loadedSessions)
                self?.syncMonitors(currentPaths: currentProjectPaths)
            }
        }
    }

    @MainActor
    private func updateSessions(_ newSessions: [Session]) {
        sessions = newSessions
    }

    /// Sync monitors with current project directories
    /// Add monitors for new projects, remove monitors for deleted projects
    @MainActor
    private func syncMonitors(currentPaths: Set<String>) {
        // Add monitors for new projects
        let newPaths = currentPaths.subtracting(monitoredPaths)
        for path in newPaths {
            let url = URL(fileURLWithPath: path)
            startDirectoryMonitor(at: url)
        }

        // Remove monitors for deleted projects (but keep parent directory monitor)
        let parentPath = Constants.claudeProjectsPath.path
        let removedPaths = monitoredPaths.subtracting(currentPaths).subtracting([parentPath])
        for path in removedPaths {
            removeMonitor(forPath: path)
        }
    }

    /// Remove monitor for a specific path
    @MainActor
    private func removeMonitor(forPath path: String) {
        // Find and cancel the source for this path
        for (index, source) in sources.enumerated().reversed() {
            let sourceId = ObjectIdentifier(source)
            if sourcePathMap[sourceId] == path {
                source.cancel()
                sources.remove(at: index)
                sourcePathMap.removeValue(forKey: sourceId)
                monitoredPaths.remove(path)
                break
            }
        }
    }

    /// Loads recent sessions and returns project paths for monitoring
    /// Returns nil on critical error (caller should keep existing data)
    /// First collects all session metadata, sorts by date, then loads summaries for top 10 only
    private static func loadRecentSessionsAndProjectPaths() async -> ([Session], Set<String>)? {
        let projectsPath = Constants.claudeProjectsPath

        guard FileManager.default.fileExists(atPath: projectsPath.path) else {
            return ([], [])
        }

        // Get project directories
        let projectDirs: [URL]
        do {
            projectDirs = try FileManager.default.contentsOfDirectory(
                at: projectsPath,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ).filter { url in
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                return isDirectory.boolValue
            }
        } catch {
            // Critical error reading parent directory - return nil to keep existing data
            print("Error reading projects directory: \(error)")
            return nil
        }

        // Collect project paths for monitoring
        let projectPaths = Set(projectDirs.map { $0.path })

        // First pass: collect only top 10 sessions using streaming selection
        // This avoids O(n log n) sort and reduces memory usage
        // Handle per-project errors gracefully (continue with other projects)
        var topSessions: [Session] = []
        topSessions.reserveCapacity(10)

        for projectDir in projectDirs {
            // Check for cancellation to abort early on frequent events
            guard !Task.isCancelled else { return nil }

            let projectId = projectDir.lastPathComponent
            do {
                let jsonlFiles = try FileManager.default.contentsOfDirectory(
                    at: projectDir,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ).filter { $0.pathExtension == "jsonl" }

                for file in jsonlFiles {
                    // Check for cancellation in inner loop for better responsiveness
                    guard !Task.isCancelled else { return nil }

                    let session = Session(filePath: file, projectId: projectId)

                    // Streaming top-10 selection: insert if qualifies
                    if topSessions.count < 10 {
                        // List not full yet - insert in sorted order
                        let insertIndex = topSessions.firstIndex { $0.lastModified < session.lastModified } ?? topSessions.count
                        topSessions.insert(session, at: insertIndex)
                    } else if session.lastModified > topSessions.last!.lastModified {
                        // Session is newer than the oldest in top 10 - insert and remove oldest
                        let insertIndex = topSessions.firstIndex { $0.lastModified < session.lastModified } ?? topSessions.count
                        topSessions.insert(session, at: insertIndex)
                        topSessions.removeLast()
                    }
                }
            } catch {
                // Per-project error - skip this project but continue with others
                print("Error reading project \(projectId): \(error)")
                continue
            }
        }

        // Check for cancellation before loading summaries
        guard !Task.isCancelled else { return nil }

        // Second pass: load summaries only for top 10 sessions
        for index in topSessions.indices {
            // Check for cancellation before each summary load
            guard !Task.isCancelled else { return nil }

            if let summary = loadSessionSummary(from: topSessions[index].filePath) {
                topSessions[index].summary = summary
            }
        }

        return (topSessions, projectPaths)
    }

    /// Loads session summary from file (called from background thread)
    /// Uses String(decoding:as:) to handle UTF-8 boundary issues gracefully
    private static func loadSessionSummary(from url: URL) -> String? {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return nil }
        defer { try? handle.close() }

        let data = handle.readData(ofLength: 4096)
        // Use String(decoding:as:) to handle incomplete UTF-8 sequences gracefully
        // (replaces invalid bytes with replacement character instead of returning nil)
        let content = String(decoding: data, as: UTF8.self)

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
        // Skip if already monitoring this path
        guard !monitoredPaths.contains(url.path) else { return }

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        monitoredPaths.insert(url.path)

        let queue = DispatchQueue(label: "com.claudesessionmonitor.recentwatcher.\(url.lastPathComponent)")

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .link],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.triggerReload()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        sources.append(source)
        sourcePathMap[ObjectIdentifier(source)] = url.path
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
