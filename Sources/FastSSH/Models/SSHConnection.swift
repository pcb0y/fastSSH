import Foundation

struct SSHConnection: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var host: String
    var port: Int = 22
    var username: String
    var authMethod: AuthMethod = .password
    var password: String = ""
    var keyPath: String = ""
    var group: String = ""

    enum AuthMethod: String, Codable, CaseIterable {
        case password
        case key
    }
}
