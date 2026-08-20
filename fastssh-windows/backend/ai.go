package backend

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// AIConfig holds AI provider configuration
type AIConfig struct {
	Provider string `json:"provider"` // openai, anthropic, deepseek, qwen, ollama, custom
	APIKey   string `json:"apiKey"`
	Endpoint string `json:"endpoint"`
	Model    string `json:"model"`
}

// AIResponse represents parsed LLM response
type AIResponse struct {
	Type    string `json:"type"` // "command", "result", "error"
	Content string `json:"content"`
}

var defaultEndpoints = map[string]string{
	"openai":    "https://api.openai.com/v1",
	"anthropic": "https://api.anthropic.com/v1",
	"deepseek":  "https://api.deepseek.com/v1",
	"qwen":      "https://dashscope.aliyuncs.com/compatible-mode/v1",
	"ollama":    "http://localhost:11434",
}

var defaultModels = map[string]string{
	"openai":    "gpt-4o-mini",
	"anthropic": "claude-sonnet-4-20250514",
	"deepseek":  "deepseek-chat",
	"qwen":      "qwen-plus",
	"ollama":    "llama3",
}

const systemPrompt = `You are an AI agent operating inside an SSH terminal session on a remote server. The user gives you a task. You accomplish it by running shell commands and observing their output.

RESPONSE FORMAT - You must respond in exactly one of these two formats:

1. To run a command:
` + "```command" + `
your_shell_command_here
` + "```" + `

2. When the task is complete (you have the final answer or have finished the operation):
` + "```result" + `
Your final answer or summary here
` + "```" + `

RULES:
- Run ONE command at a time, then wait for output.
- Use the command output to decide your next step.
- Never guess - always verify by running commands.
- If a command fails, try an alternative approach.
- When you have enough information or completed the task, respond with ` + "```result" + `.
- Keep results concise and informative.
- Do not include any text outside of the code blocks.`

// AIService handles AI interactions
type AIService struct {
	Config AIConfig
}

func (s *AIService) effectiveEndpoint() string {
	if s.Config.Endpoint != "" {
		return s.Config.Endpoint
	}
	if ep, ok := defaultEndpoints[s.Config.Provider]; ok {
		return ep
	}
	return "https://api.openai.com/v1"
}

func (s *AIService) effectiveModel() string {
	if s.Config.Model != "" {
		return s.Config.Model
	}
	if m, ok := defaultModels[s.Config.Provider]; ok {
		return m
	}
	return "gpt-4o-mini"
}

// Chat sends messages to the LLM and returns parsed response
func (s *AIService) Chat(messages []map[string]string) (*AIResponse, error) {
	var raw string
	var err error

	switch s.Config.Provider {
	case "anthropic":
		raw, err = s.callAnthropic(messages)
	case "ollama":
		raw, err = s.callOllama(messages)
	default:
		raw, err = s.callOpenAICompatible(messages)
	}

	if err != nil {
		return &AIResponse{Type: "error", Content: err.Error()}, err
	}

	return s.parseResponse(raw), nil
}

func (s *AIService) parseResponse(text string) *AIResponse {
	trimmed := strings.TrimSpace(text)

	// Parse ```command\n...\n```
	if idx := strings.Index(trimmed, "```command\n"); idx >= 0 {
		after := trimmed[idx+len("```command\n"):]
		if end := strings.Index(after, "```"); end >= 0 {
			cmd := strings.TrimSpace(after[:end])
			return &AIResponse{Type: "command", Content: cmd}
		}
	}

	// Parse ```result\n...\n```
	if idx := strings.Index(trimmed, "```result\n"); idx >= 0 {
		after := trimmed[idx+len("```result\n"):]
		if end := strings.Index(after, "```"); end >= 0 {
			result := strings.TrimSpace(after[:end])
			return &AIResponse{Type: "result", Content: result}
		}
	}

	// Fallback
	if !strings.Contains(trimmed, "\n") && len(trimmed) < 200 {
		return &AIResponse{Type: "command", Content: trimmed}
	}
	return &AIResponse{Type: "result", Content: trimmed}
}

func (s *AIService) callOpenAICompatible(messages []map[string]string) (string, error) {
	endpoint := s.effectiveEndpoint()
	url := endpoint + "/chat/completions"

	apiMessages := []map[string]string{{"role": "system", "content": systemPrompt}}
	apiMessages = append(apiMessages, messages...)

	body := map[string]interface{}{
		"model":       s.effectiveModel(),
		"messages":    apiMessages,
		"temperature": 0.1,
		"max_tokens":  1000,
	}

	jsonBody, _ := json.Marshal(body)
	req, _ := http.NewRequest("POST", url, bytes.NewReader(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.Config.APIKey)

	client := &http.Client{Timeout: 60 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("API error (%d): %s", resp.StatusCode, string(data))
	}

	var result struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(data, &result); err != nil {
		return "", fmt.Errorf("parse error: %w", err)
	}
	if len(result.Choices) == 0 {
		return "", fmt.Errorf("no choices in response")
	}
	return result.Choices[0].Message.Content, nil
}

func (s *AIService) callAnthropic(messages []map[string]string) (string, error) {
	endpoint := s.effectiveEndpoint()
	url := endpoint + "/messages"

	apiMessages := make([]map[string]string, 0, len(messages))
	for _, msg := range messages {
		role := msg["role"]
		if role != "assistant" {
			role = "user"
		}
		apiMessages = append(apiMessages, map[string]string{"role": role, "content": msg["content"]})
	}

	body := map[string]interface{}{
		"model":      s.effectiveModel(),
		"max_tokens": 1000,
		"system":     systemPrompt,
		"messages":   apiMessages,
	}

	jsonBody, _ := json.Marshal(body)
	req, _ := http.NewRequest("POST", url, bytes.NewReader(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", s.Config.APIKey)
	req.Header.Set("anthropic-version", "2023-06-01")

	client := &http.Client{Timeout: 60 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("API error (%d): %s", resp.StatusCode, string(data))
	}

	var result struct {
		Content []struct {
			Text string `json:"text"`
		} `json:"content"`
	}
	if err := json.Unmarshal(data, &result); err != nil {
		return "", fmt.Errorf("parse error: %w", err)
	}
	if len(result.Content) == 0 {
		return "", fmt.Errorf("no content in response")
	}
	return result.Content[0].Text, nil
}

func (s *AIService) callOllama(messages []map[string]string) (string, error) {
	endpoint := s.effectiveEndpoint()
	url := endpoint + "/api/chat"

	apiMessages := []map[string]string{{"role": "system", "content": systemPrompt}}
	apiMessages = append(apiMessages, messages...)

	body := map[string]interface{}{
		"model":    s.effectiveModel(),
		"messages": apiMessages,
		"stream":   false,
	}

	jsonBody, _ := json.Marshal(body)
	req, _ := http.NewRequest("POST", url, bytes.NewReader(jsonBody))
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 120 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("API error (%d): %s", resp.StatusCode, string(data))
	}

	var result struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
	}
	if err := json.Unmarshal(data, &result); err != nil {
		return "", fmt.Errorf("parse error: %w", err)
	}
	return result.Message.Content, nil
}

// FetchModels fetches available models from the provider
func (s *AIService) FetchModels() ([]string, error) {
	switch s.Config.Provider {
	case "ollama":
		return s.fetchOllamaModels()
	case "anthropic":
		return []string{
			"claude-sonnet-4-20250514", "claude-opus-4-20250514",
			"claude-haiku-4-20250514", "claude-3-5-sonnet-20241022",
		}, nil
	default:
		return s.fetchOpenAIModels()
	}
}

func (s *AIService) fetchOpenAIModels() ([]string, error) {
	endpoint := s.effectiveEndpoint()
	url := endpoint + "/models"

	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("Authorization", "Bearer "+s.Config.APIKey)

	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("failed to fetch models: %d", resp.StatusCode)
	}

	data, _ := io.ReadAll(resp.Body)
	var result struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(data, &result); err != nil {
		return nil, err
	}

	models := make([]string, 0, len(result.Data))
	for _, m := range result.Data {
		models = append(models, m.ID)
	}
	return models, nil
}

func (s *AIService) fetchOllamaModels() ([]string, error) {
	endpoint := s.effectiveEndpoint()
	url := endpoint + "/api/tags"

	req, _ := http.NewRequest("GET", url, nil)
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("failed to fetch models: %d", resp.StatusCode)
	}

	data, _ := io.ReadAll(resp.Body)
	var result struct {
		Models []struct {
			Name string `json:"name"`
		} `json:"models"`
	}
	if err := json.Unmarshal(data, &result); err != nil {
		return nil, err
	}

	models := make([]string, 0, len(result.Models))
	for _, m := range result.Models {
		models = append(models, m.Name)
	}
	return models, nil
}
