import SwiftUI

@main
struct ClaudeSessionMonitorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Claude Session Monitor") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: Constants.appName,
                            .applicationVersion: "1.0.0",
                            .credits: NSAttributedString(
                                string: "A session log viewer for Claude Code"
                            )
                        ]
                    )
                }
            }
        }
    }
}
