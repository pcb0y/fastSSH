import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var languageManager: LanguageManager

    var body: some View {
        VStack(spacing: 0) {
        List {
            // Active Sessions
            if !appState.sessions.isEmpty {
                Section("active.sessions".localized) {
                    ForEach(appState.sessions) { session in
                        HStack {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                            Text(session.connection.name)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                appState.removeSession(session)
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appState.activeSessionId = session.id
                        }
                        .padding(.vertical, 2)
                        .background(
                            appState.activeSessionId == session.id ?
                            Color.accentColor.opacity(0.1) : Color.clear
                        )
                        .cornerRadius(4)
                    }
                }
            }

            // Saved Connections
            Section("connections".localized) {
                ForEach(groupedConnections.keys.sorted(), id: \.self) { group in
                    if group.isEmpty {
                        ForEach(groupedConnections[group] ?? []) { conn in
                            connectionRow(conn)
                        }
                    } else {
                        DisclosureGroup(group) {
                            ForEach(groupedConnections[group] ?? []) { conn in
                                connectionRow(conn)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem {
                Button {
                    appState.editingConnection = nil
                    appState.showConnectionDialog = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }

            // Language picker at bottom
            Divider()
            HStack {
                Image(systemName: "globe")
                    .foregroundColor(.secondary)
                Picker("", selection: $languageManager.currentLanguage) {
                    ForEach(LanguageManager.supportedLanguages) { lang in
                        Text(lang.name).tag(lang.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        } // end VStack
    }

    private var groupedConnections: [String: [SSHConnection]] {
        Dictionary(grouping: appState.connections, by: { $0.group })
    }

    private func connectionRow(_ conn: SSHConnection) -> some View {
        HStack {
            Image(systemName: "server.rack")
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(conn.name)
                    .fontWeight(.medium)
                Text("\(conn.username)@\(conn.host):\(conn.port)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            connectTo(conn)
        }
        .contextMenu {
            Button("connect".localized) { connectTo(conn) }
            Divider()
            Button("edit".localized) {
                appState.editingConnection = conn
                appState.showConnectionDialog = true
            }
            Button("delete".localized, role: .destructive) {
                appState.deleteConnection(conn)
            }
        }
    }

    private func connectTo(_ conn: SSHConnection) {
        let session = SSHSession(connection: conn)
        appState.addSession(session)
        Task {
            await session.connect()
        }
    }
}
