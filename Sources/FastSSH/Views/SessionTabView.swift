import SwiftUI

struct SessionTabView: View {
    @ObservedObject var session: SSHSession
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                tabButton("tab.terminal".localized, systemImage: "terminal", index: 0)
                tabButton("tab.files".localized, systemImage: "folder", index: 1)
                Spacer()
                if let error = session.error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.trailing, 12)
                }
                if !session.isConnected {
                    Label("status.disconnected".localized, systemImage: "wifi.slash")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.trailing, 12)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(.bar)

            Divider()

            // Content
            switch selectedTab {
            case 0:
                TerminalView(session: session)
            case 1:
                FileBrowserView(session: session)
            default:
                EmptyView()
            }
        }
    }

    private func tabButton(_ title: String, systemImage: String, index: Int) -> some View {
        Button {
            selectedTab = index
        } label: {
            Label(title, systemImage: systemImage)
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selectedTab == index ? Color.accentColor.opacity(0.1) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .foregroundColor(selectedTab == index ? .accentColor : .secondary)
    }
}
