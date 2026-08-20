import SwiftUI

struct AIMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String

    enum Role {
        case user
        case assistant
        case command
        case output
        case result
        case error
    }
}

struct AIAssistantView: View {
    @ObservedObject var session: SSHSession
    @EnvironmentObject var aiConfig: AIConfigStore
    @State private var inputText = ""
    @State private var messages: [AIMessage] = []
    @State private var isLoading = false
    @State private var showSettings = false
    @State private var agentTask: Task<Void, Never>?

    private let maxIterations = 15

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("ai.agent".localized)
                    .font(.headline)
                Spacer()
                if isLoading {
                    Button {
                        stopAgent()
                    } label: {
                        Image(systemName: "stop.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("ai.stop".localized)
                }
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { msg in
                            messageView(msg)
                                .id(msg.id)
                        }
                        if isLoading {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("ai.thinking".localized)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .id("loading")
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation {
                        if let last = messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input
            HStack(spacing: 8) {
                TextField("ai.placeholder".localized, text: $inputText)
                    .textFieldStyle(.plain)
                    .onSubmit { sendMessage() }
                    .disabled(isLoading)

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundColor(inputText.isEmpty || isLoading ? .secondary : .purple)
                .disabled(inputText.isEmpty || isLoading)
            }
            .padding(10)
            .background(.bar)
        }
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showSettings) {
            AISettingsView()
        }
    }

    // MARK: - Message Views

    @ViewBuilder
    private func messageView(_ msg: AIMessage) -> some View {
        switch msg.role {
        case .user:
            HStack {
                Spacer()
                Text(msg.content)
                    .padding(8)
                    .background(Color.purple.opacity(0.15))
                    .cornerRadius(8)
            }
            .padding(.horizontal, 12)

        case .command:
            VStack(alignment: .leading, spacing: 2) {
                Label("Command", systemImage: "terminal")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(msg.content)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.08))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 12)

        case .output:
            VStack(alignment: .leading, spacing: 2) {
                Label("Output", systemImage: "text.alignleft")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(msg.content)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(10)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 12)

        case .assistant, .result:
            VStack(alignment: .leading, spacing: 4) {
                Label("ai.result".localized, systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.green)
                Text(msg.content)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(8)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(msg.content, forType: .string)
                } label: {
                    Label("ai.copy".localized, systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)

        case .error:
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(msg.content)
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Agent Loop

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        messages.append(AIMessage(role: .user, content: text))
        inputText = ""
        isLoading = true

        agentTask = Task {
            await runAgentLoop(task: text)
            isLoading = false
        }
    }

    private func stopAgent() {
        agentTask?.cancel()
        agentTask = nil
        isLoading = false
        messages.append(AIMessage(role: .error, content: "Agent stopped by user."))
    }

    private func runAgentLoop(task userTask: String) async {
        let config = aiConfig.config
        guard !config.apiKey.isEmpty || config.provider == .ollama else {
            messages.append(AIMessage(role: .error, content: AIError.notConfigured.localizedDescription))
            return
        }

        let service = AIService(config: config)

        // Build conversation history
        var conversation: [[String: String]] = [
            ["role": "user", "content": userTask]
        ]

        for _ in 0..<maxIterations {
            guard !Task.isCancelled else { return }

            do {
                let response = try await service.chat(messages: conversation)

                switch response.type {
                case .command(let cmd):
                    // Show command in chat
                    await MainActor.run {
                        messages.append(AIMessage(role: .command, content: cmd))
                    }

                    // Execute command via SSH
                    guard session.isConnected else {
                        await MainActor.run {
                            messages.append(AIMessage(role: .error, content: "SSH session disconnected."))
                        }
                        return
                    }

                    let output = await session.executeCommand(cmd)
                    let trimmedOutput = String(output.prefix(4000)) // Limit output size

                    // Show output in chat
                    await MainActor.run {
                        messages.append(AIMessage(role: .output, content: trimmedOutput.isEmpty ? "(no output)" : trimmedOutput))
                    }

                    // Feed back to LLM
                    conversation.append(["role": "assistant", "content": "```command\n\(cmd)\n```"])
                    conversation.append(["role": "user", "content": "Command output:\n\(trimmedOutput.isEmpty ? "(no output)" : trimmedOutput)"])

                case .result(let result):
                    // Agent finished
                    await MainActor.run {
                        messages.append(AIMessage(role: .result, content: result))
                    }
                    return

                case .error(let err):
                    await MainActor.run {
                        messages.append(AIMessage(role: .error, content: err))
                    }
                    return
                }
            } catch {
                await MainActor.run {
                    messages.append(AIMessage(role: .error, content: error.localizedDescription))
                }
                return
            }

            // Small delay between iterations
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        // Max iterations reached
        await MainActor.run {
            messages.append(AIMessage(role: .error, content: "Agent reached maximum iterations (\(maxIterations)). Stopping."))
        }
    }
}
