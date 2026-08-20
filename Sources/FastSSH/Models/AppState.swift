import SwiftUI
import Foundation

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
}
