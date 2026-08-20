import SwiftUI

struct SessionTabView: View {
    @ObservedObject var session: SSHSession
    @State private var selectedTab = 0
    @State private var showAIPanel = false

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                tabButton("tab.terminal".localized, systemImage: "terminal", index: 0)
                tabButton("tab.files".localized, systemImage: "folder", index: 1)
                tabButton("tab.monitor".localized, systemImage: "gauge.with.dots.needle.33percent", index: 2)
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
                // AI toggle button - prominent pill style
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAIPanel.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .bold))
                        Text("ai.agent".localized)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(showAIPanel
                                  ? LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing)
                                  : LinearGradient(colors: [.purple.opacity(0.15), .indigo.opacity(0.15)], startPoint: .leading, endPoint: .trailing))
                    )
                    .overlay(
                        Capsule()
                            .stroke(showAIPanel ? Color.clear : Color.purple.opacity(0.5), lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
                .foregroundColor(showAIPanel ? .white : .purple)
                .padding(.trailing, 10)
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(.bar)

            Divider()

            // Content + AI Panel
            HStack(spacing: 0) {
                // Main content
                Group {
                    switch selectedTab {
                    case 0:
                        TerminalView(session: session)
                    case 1:
                        FileBrowserView(session: session)
                    case 2:
                        ServerMonitorView(session: session)
                    default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // AI Panel
                if showAIPanel {
                    Divider()
                    AIAssistantView(session: session)
                }
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
