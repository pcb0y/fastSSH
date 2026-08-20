import Foundation
import SwiftUI

enum AIProviderType: String, Codable, CaseIterable {
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    case deepseek = "DeepSeek"
    case qwen = "Qwen (通义千问)"
    case ollama = "Ollama"
    case custom = "Custom (OpenAI Compatible)"

    var defaultEndpoint: String {
        switch self {
        case .openAI: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .qwen: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .ollama: return "http://localhost:11434"
        case .custom: return "https://api.example.com/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: return "gpt-4o-mini"
        case .anthropic: return "claude-sonnet-4-20250514"
        case .deepseek: return "deepseek-chat"
        case .qwen: return "qwen-plus"
        case .ollama: return "llama3"
        case .custom: return "gpt-3.5-turbo"
        }
    }

    /// Built-in model list for when API key is not yet configured
    var builtinModels: [String] {
        switch self {
        case .openAI:
            return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-4", "gpt-3.5-turbo", "o1", "o1-mini", "o3-mini"]
        case .anthropic:
            return ["claude-sonnet-4-20250514", "claude-opus-4-20250514", "claude-haiku-4-20250514", "claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022"]
        case .deepseek:
            return ["deepseek-chat", "deepseek-coder", "deepseek-reasoner"]
        case .qwen:
            return ["qwen-plus", "qwen-turbo", "qwen-max", "qwen-long", "qwen-vl-plus", "qwen-vl-max"]
        case .ollama:
            return []
        case .custom:
            return []
        }
    }
}

struct AIConfig: Codable {
    var provider: AIProviderType = .openAI
    var apiKey: String = ""
    var endpoint: String = ""
    var model: String = ""

    var effectiveEndpoint: String {
        endpoint.isEmpty ? provider.defaultEndpoint : endpoint
    }

    var effectiveModel: String {
        model.isEmpty ? provider.defaultModel : model
    }
}

@MainActor
class AIConfigStore: ObservableObject {
    static let shared = AIConfigStore()

    @Published var config: AIConfig {
        didSet { save() }
    }

    private let configURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("FastSSH")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        configURL = dir.appendingPathComponent("ai_config.json")

        if let data = try? Data(contentsOf: configURL),
           let loaded = try? JSONDecoder().decode(AIConfig.self, from: data) {
            config = loaded
        } else {
            config = AIConfig()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: configURL, options: .atomic)
    }
}
