import Foundation

/// AI Agent that iteratively executes commands and reasons about results
struct AIService {
    let config: AIConfig

    private static let systemPrompt = """
    You are an AI agent operating inside an SSH terminal session on a remote server. \
    The user gives you a task. You accomplish it by running shell commands and observing their output.

    RESPONSE FORMAT - You must respond in exactly one of these two formats:

    1. To run a command:
    ```command
    your_shell_command_here
    ```

    2. When the task is complete (you have the final answer or have finished the operation):
    ```result
    Your final answer or summary here
    ```

    RULES:
    - Run ONE command at a time, then wait for output.
    - Use the command output to decide your next step.
    - Never guess - always verify by running commands.
    - If a command fails, try an alternative approach.
    - When you have enough information or completed the task, respond with ```result.
    - Keep results concise and informative.
    - Do not include any text outside of the code blocks.
    """

    struct AgentResponse {
        enum ResponseType {
            case command(String)
            case result(String)
            case error(String)
        }
        let type: ResponseType
    }

    /// Send a conversation to the LLM and parse its response
    func chat(messages: [[String: String]]) async throws -> AgentResponse {
        let raw: String
        switch config.provider {
        case .openAI, .deepseek, .qwen, .custom:
            raw = try await callOpenAICompatible(messages: messages)
        case .anthropic:
            raw = try await callAnthropic(messages: messages)
        case .ollama:
            raw = try await callOllama(messages: messages)
        }
        return parseResponse(raw)
    }

    private func parseResponse(_ text: String) -> AgentResponse {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse ```command\n...\n```
        if let range = trimmed.range(of: "```command\n") ?? trimmed.range(of: "```command\r\n") {
            let afterTag = trimmed[range.upperBound...]
            if let endRange = afterTag.range(of: "```") {
                let cmd = String(afterTag[..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                return AgentResponse(type: .command(cmd))
            }
        }

        // Parse ```result\n...\n```
        if let range = trimmed.range(of: "```result\n") ?? trimmed.range(of: "```result\r\n") {
            let afterTag = trimmed[range.upperBound...]
            if let endRange = afterTag.range(of: "```") {
                let result = String(afterTag[..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                return AgentResponse(type: .result(result))
            }
        }

        // Fallback: if it looks like a command (single line, no spaces at start suggesting prose)
        if !trimmed.contains("\n") && !trimmed.hasPrefix("```") && trimmed.count < 200 {
            return AgentResponse(type: .command(trimmed))
        }

        // Otherwise treat as result
        return AgentResponse(type: .result(trimmed))
    }

    // MARK: - OpenAI Compatible

    private func callOpenAICompatible(messages: [[String: String]]) async throws -> String {
        let url = URL(string: "\(config.effectiveEndpoint)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        var apiMessages: [[String: String]] = [["role": "system", "content": Self.systemPrompt]]
        apiMessages.append(contentsOf: messages)

        let body: [String: Any] = [
            "model": config.effectiveModel,
            "messages": apiMessages,
            "temperature": 0.1,
            "max_tokens": 1000
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            let errMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.apiError(errMsg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.parseError
        }

        return content
    }

    // MARK: - Anthropic

    private func callAnthropic(messages: [[String: String]]) async throws -> String {
        let url = URL(string: "\(config.effectiveEndpoint)/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 60

        // Convert messages for Anthropic format
        let apiMessages: [[String: String]] = messages.map { msg in
            ["role": msg["role"] == "assistant" ? "assistant" : "user", "content": msg["content"] ?? ""]
        }

        let body: [String: Any] = [
            "model": config.effectiveModel,
            "max_tokens": 1000,
            "system": Self.systemPrompt,
            "messages": apiMessages
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            let errMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.apiError(errMsg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw AIError.parseError
        }

        return text
    }

    // MARK: - Ollama

    private func callOllama(messages: [[String: String]]) async throws -> String {
        let url = URL(string: "\(config.effectiveEndpoint)/api/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        var apiMessages: [[String: String]] = [["role": "system", "content": Self.systemPrompt]]
        apiMessages.append(contentsOf: messages)

        let body: [String: Any] = [
            "model": config.effectiveModel,
            "messages": apiMessages,
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            let errMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.apiError(errMsg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.parseError
        }

        return content
    }
}

enum AIError: Error, LocalizedError {
    case apiError(String)
    case parseError
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .apiError(let msg): return "ai.error.api".localized(msg)
        case .parseError: return "ai.error.parse".localized
        case .notConfigured: return "ai.error.notconfigured".localized
        }
    }
}
