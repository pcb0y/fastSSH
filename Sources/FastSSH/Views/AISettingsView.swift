import SwiftUI

struct AISettingsView: View {
    @EnvironmentObject var aiConfig: AIConfigStore
    @Environment(\.dismiss) var dismiss
    @State private var availableModels: [String] = []
    @State private var isFetchingModels = false
    @State private var fetchError: String?

    var body: some View {
        VStack(spacing: 0) {
            Text("ai.settings".localized)
                .font(.headline)
                .padding()

            Divider()

            Form {
                Picker("ai.provider".localized, selection: $aiConfig.config.provider) {
                    ForEach(AIProviderType.allCases, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .onChange(of: aiConfig.config.provider) { _, _ in
                    // Reset model when switching provider
                    aiConfig.config.model = ""
                    availableModels = []
                    fetchError = nil
                    fetchModelsIfReady()
                }

                if aiConfig.config.provider != .ollama {
                    SecureField("API Key", text: $aiConfig.config.apiKey)
                        .onChange(of: aiConfig.config.apiKey) { _, newValue in
                            if !newValue.isEmpty {
                                fetchModelsIfReady()
                            }
                        }
                }

                // Endpoint (pre-filled, editable)
                TextField("ai.endpoint".localized, text: $aiConfig.config.endpoint, prompt: Text(aiConfig.config.provider.defaultEndpoint))

                // Model: combo of picker + manual input
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        let models = availableModels.isEmpty ? aiConfig.config.provider.builtinModels : availableModels
                        if !models.isEmpty {
                            Picker("ai.model".localized, selection: $aiConfig.config.model) {
                                Text(aiConfig.config.provider.defaultModel + " (\("default".localized))").tag("")
                                ForEach(models, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                                // If current model is custom (not in list), show it
                                if !aiConfig.config.model.isEmpty && !models.contains(aiConfig.config.model) {
                                    Text(aiConfig.config.model + " (\("ai.custom.model".localized))").tag(aiConfig.config.model)
                                }
                            }
                        } else {
                            TextField("ai.model".localized, text: $aiConfig.config.model, prompt: Text(aiConfig.config.provider.defaultModel))
                        }

                        if isFetchingModels {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button {
                                fetchModelsIfReady()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                            .help("ai.fetch.models".localized)
                        }
                    }
                    // Manual model input
                    TextField("ai.custom.model.input".localized, text: $aiConfig.config.model, prompt: Text(aiConfig.config.provider.defaultModel))
                        .font(.caption)
                }

                if let error = fetchError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .formStyle(.grouped)
            .padding()

            Divider()

            HStack {
                Spacer()
                Button("OK") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 380)
        .onAppear {
            fetchModelsIfReady()
        }
    }

    private func fetchModelsIfReady() {
        let config = aiConfig.config
        // Ollama doesn't need API key
        guard config.provider == .ollama || !config.apiKey.isEmpty else { return }
        isFetchingModels = true
        fetchError = nil

        Task {
            do {
                let models = try await fetchModelList(config: config)
                await MainActor.run {
                    availableModels = models
                    isFetchingModels = false
                }
            } catch {
                await MainActor.run {
                    fetchError = error.localizedDescription
                    availableModels = []
                    isFetchingModels = false
                }
            }
        }
    }

    private func fetchModelList(config: AIConfig) async throws -> [String] {
        switch config.provider {
        case .anthropic:
            return try await fetchAnthropicModels(config: config)
        case .ollama:
            return try await fetchOllamaModels(config: config)
        case .openAI, .deepseek, .qwen, .custom:
            return try await fetchOpenAIModels(config: config)
        }
    }

    // OpenAI-compatible: GET /models
    private func fetchOpenAIModels(config: AIConfig) async throws -> [String] {
        let endpoint = config.effectiveEndpoint
        let url = URL(string: "\(endpoint)/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            let errMsg = String(data: data, encoding: .utf8) ?? "HTTP error"
            throw AIError.apiError(errMsg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArr = json["data"] as? [[String: Any]] else {
            return []
        }

        return dataArr.compactMap { $0["id"] as? String }.sorted()
    }

    // Anthropic: GET /models
    private func fetchAnthropicModels(config: AIConfig) async throws -> [String] {
        let endpoint = config.effectiveEndpoint
        let url = URL(string: "\(endpoint)/models")!
        var request = URLRequest(url: url)
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            // Anthropic may not have /models endpoint, return hardcoded list
            return ["claude-sonnet-4-20250514", "claude-opus-4-20250514", "claude-haiku-4-20250514", "claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022"]
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArr = json["data"] as? [[String: Any]] else {
            return ["claude-sonnet-4-20250514", "claude-opus-4-20250514", "claude-haiku-4-20250514", "claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022"]
        }

        return dataArr.compactMap { $0["id"] as? String }.sorted()
    }

    // Ollama: GET /api/tags
    private func fetchOllamaModels(config: AIConfig) async throws -> [String] {
        let endpoint = config.effectiveEndpoint
        let url = URL(string: "\(endpoint)/api/tags")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            return []
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            return []
        }

        return models.compactMap { $0["name"] as? String }.sorted()
    }
}
