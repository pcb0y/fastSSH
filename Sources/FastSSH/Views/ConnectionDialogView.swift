import SwiftUI

struct ConnectionDialogView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    let connection: SSHConnection?

    @State private var name = ""
    @State private var host = ""
    @State private var port = 22
    @State private var username = "root"
    @State private var authMethod: SSHConnection.AuthMethod = .password
    @State private var password = ""
    @State private var keyPath = "~/.ssh/id_rsa"
    @State private var group = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text(connection == nil ? "new.connection".localized : "edit.connection".localized)
                .font(.headline)
                .padding()

            Divider()

            // Form
            Form {
                TextField("field.name".localized, text: $name)
                HStack {
                    TextField("field.host".localized, text: $host)
                    TextField("field.port".localized, value: $port, format: .number)
                        .frame(width: 60)
                }
                TextField("field.username".localized, text: $username)

                Picker("field.auth.method".localized, selection: $authMethod) {
                    Text("auth.password".localized).tag(SSHConnection.AuthMethod.password)
                    Text("auth.key".localized).tag(SSHConnection.AuthMethod.key)
                }

                if authMethod == .password {
                    SecureField("field.password".localized, text: $password)
                } else {
                    TextField("field.key.path".localized, text: $keyPath)
                }

                TextField("field.group".localized, text: $group)
            }
            .formStyle(.grouped)
            .padding()

            Divider()

            // Actions
            HStack {
                Button("cancel".localized) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(connection == nil ? "add".localized : "save".localized) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || host.isEmpty || username.isEmpty)
            }
            .padding()
        }
        .frame(width: 450, height: 420)
        .onAppear {
            if let conn = connection {
                name = conn.name
                host = conn.host
                port = conn.port
                username = conn.username
                authMethod = conn.authMethod
                password = conn.password
                keyPath = conn.keyPath
                group = conn.group
            }
        }
    }

    private func save() {
        var conn = connection ?? SSHConnection(name: "", host: "", username: "")
        conn.name = name
        conn.host = host
        conn.port = port
        conn.username = username
        conn.authMethod = authMethod
        conn.password = password
        conn.keyPath = keyPath
        conn.group = group

        if connection == nil {
            appState.addConnection(conn)
        } else {
            appState.updateConnection(conn)
        }
        dismiss()
    }
}
