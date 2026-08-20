import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
class AppState: ObservableObject {
    @Published var connections: [SSHConnection] = []
    @Published var sessions: [SSHSession] = []
    @Published var activeSessionId: UUID?
    @Published var showConnectionDialog = false
    @Published var editingConnection: SSHConnection?

    private let configURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("FastSSH")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        configURL = dir.appendingPathComponent("connections.json")
        loadConnections()
    }

    func loadConnections() {
        guard let data = try? Data(contentsOf: configURL) else { return }
        connections = (try? JSONDecoder().decode([SSHConnection].self, from: data)) ?? []
    }

    func saveConnections() {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        try? data.write(to: configURL, options: .atomic)
    }

    func addConnection(_ conn: SSHConnection) {
        connections.append(conn)
        saveConnections()
    }

    func updateConnection(_ conn: SSHConnection) {
        if let idx = connections.firstIndex(where: { $0.id == conn.id }) {
            connections[idx] = conn
            saveConnections()
        }
    }

    func deleteConnection(_ conn: SSHConnection) {
        connections.removeAll { $0.id == conn.id }
        saveConnections()
    }

    func addSession(_ session: SSHSession) {
        sessions.append(session)
        activeSessionId = session.id
    }

    func removeSession(_ session: SSHSession) {
        session.disconnect()
        sessions.removeAll { $0.id == session.id }
        if activeSessionId == session.id {
            activeSessionId = sessions.last?.id
        }
    }

    var activeSession: SSHSession? {
        sessions.first { $0.id == activeSessionId }
    }

    // MARK: - Import / Export

    func exportConnections() {
        let panel = NSSavePanel()
        panel.title = "export.title".localized
        panel.nameFieldStringValue = "FastSSH_Connections.json"
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(connections) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func importConnections() {
        let panel = NSOpenPanel()
        panel.title = "import.title".localized
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        guard let imported = try? JSONDecoder().decode([SSHConnection].self, from: data) else { return }

        // Merge: skip duplicates by host+username+port
        var added = 0
        for var conn in imported {
            let exists = connections.contains {
                $0.host == conn.host && $0.username == conn.username && $0.port == conn.port
            }
            if !exists {
                conn.id = UUID() // assign new ID to avoid conflicts
                connections.append(conn)
                added += 1
            }
        }
        saveConnections()
        importResult = "import.result".localized(added, imported.count)
    }

    @Published var importResult: String?
}
