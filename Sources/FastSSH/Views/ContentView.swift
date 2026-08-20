import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if let session = appState.activeSession {
                SessionTabView(session: session)
            } else {
                WelcomeView()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $appState.showConnectionDialog) {
            ConnectionDialogView(connection: appState.editingConnection)
        }
    }
}

struct WelcomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("app.title".localized)
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("welcome.subtitle".localized)
                .foregroundColor(.secondary)
            Button("new.connection".localized) {
                appState.showConnectionDialog = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
