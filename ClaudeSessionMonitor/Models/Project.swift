import Foundation

struct Project: Identifiable, Hashable {
    let id: String
    let path: URL
    let displayName: String
    let actualPath: String?

    init(directoryURL: URL) {
        self.id = directoryURL.lastPathComponent
        self.path = directoryURL

        let dirName = directoryURL.lastPathComponent

        if dirName.hasPrefix("-Users-") {
            // Extract the path after "-Users-{username}-"
            var remaining = dirName.dropFirst(1) // Remove leading "-"

            // Find and remove "Users-{username}-" part
            if let usersRange = remaining.range(of: "Users-") {
                remaining = remaining[usersRange.upperBound...]
                if let usernameEndIndex = remaining.firstIndex(of: "-") {
                    remaining = remaining[remaining.index(after: usernameEndIndex)...]
                }
            }

            let pathPart = String(remaining)
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

            // Try to find the actual path by checking the file system
            if let resolvedPath = Project.resolveActualPath(pathPart: pathPart, homeDir: homeDir) {
                self.actualPath = resolvedPath
                self.displayName = "~/" + resolvedPath.replacingOccurrences(of: homeDir + "/", with: "")
            } else {
                // Fallback: simple replacement (may not be accurate)
                let pathString = pathPart.replacingOccurrences(of: "-", with: "/")
                self.actualPath = nil
                self.displayName = "~/" + pathString
            }
        } else {
            self.displayName = dirName
            self.actualPath = nil
        }
    }

    /// Resolve the actual file system path by progressively building the path
    private static func resolveActualPath(pathPart: String, homeDir: String) -> String? {
        let components = pathPart.split(separator: "-", omittingEmptySubsequences: false)
        guard !components.isEmpty else { return nil }

        var currentPath = homeDir
        var resolvedComponents: [String] = []
        var i = 0

        while i < components.count {
            // Try to find the longest matching directory name
            var found = false

            // Try progressively longer combinations (with - replaced by _ or kept as -)
            for endIdx in (i..<components.count).reversed() {
                let candidateComponents = components[i...endIdx]
                let candidateWithDash = candidateComponents.joined(separator: "-")
                let candidateWithUnderscore = candidateComponents.joined(separator: "_")

                // Check if directory exists with underscore
                let pathWithUnderscore = currentPath + "/" + candidateWithUnderscore
                if FileManager.default.fileExists(atPath: pathWithUnderscore) {
                    currentPath = pathWithUnderscore
                    resolvedComponents.append(candidateWithUnderscore)
                    i = endIdx + 1
                    found = true
                    break
                }

                // Check if directory exists with dash
                let pathWithDash = currentPath + "/" + candidateWithDash
                if FileManager.default.fileExists(atPath: pathWithDash) {
                    currentPath = pathWithDash
                    resolvedComponents.append(candidateWithDash)
                    i = endIdx + 1
                    found = true
                    break
                }
            }

            if !found {
                // Single component
                let component = String(components[i])
                let testPath = currentPath + "/" + component
                if FileManager.default.fileExists(atPath: testPath) {
                    currentPath = testPath
                    resolvedComponents.append(component)
                } else {
                    resolvedComponents.append(component)
                    currentPath = testPath
                }
                i += 1
            }
        }

        let result = resolvedComponents.joined(separator: "/")

        // Verify the final path exists
        let finalPath = homeDir + "/" + result
        if FileManager.default.fileExists(atPath: finalPath) {
            return result
        }

        return nil
    }
}
