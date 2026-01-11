import SwiftUI

struct SettingsView: View {
    @Binding var showTypeColumn: Bool
    @Binding var showTimeColumn: Bool
    @Binding var showRoleColumn: Bool
    @Binding var showEmptyMessages: Bool
    @Binding var rememberLastProject: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Settings content
            Form {
                Section("Display Columns") {
                    Toggle("Show Type Column", isOn: $showTypeColumn)
                    Toggle("Show Time Column", isOn: $showTimeColumn)
                    Toggle("Show Role Column", isOn: $showRoleColumn)
                }

                Section("Message Filter") {
                    Toggle("Show Empty Messages", isOn: $showEmptyMessages)
                }

                Section("Startup") {
                    Toggle("Remember Last Project", isOn: $rememberLastProject)
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Claude Projects Path")
                        Spacer()
                        Text(Constants.claudeProjectsPath.path)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .formStyle(.grouped)
            .padding()
        }
        .frame(width: 400, height: 300)
    }
}

#Preview {
    SettingsView(
        showTypeColumn: .constant(true),
        showTimeColumn: .constant(true),
        showRoleColumn: .constant(true),
        showEmptyMessages: .constant(false),
        rememberLastProject: .constant(true)
    )
}
