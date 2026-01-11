import Foundation

enum Constants {
    static let claudeProjectsPath: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude/projects")
    }()

    static let appName = "Claude Session Monitor"

    enum ColumnWidths {
        static let type: CGFloat = 80
        static let time: CGFloat = 80
        static let role: CGFloat = 70
        static let content: CGFloat = 400
    }

    enum SidebarWidths {
        static let projectList: CGFloat = 180
        static let sessionList: CGFloat = 180
    }
}
