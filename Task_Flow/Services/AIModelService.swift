import Foundation

/// Fetches available models from AI provider APIs.
actor AIModelService {
    static let shared = AIModelService()

    struct AIModel: Identifiable, Hashable {
        let id: String
        let name: String
    }

    enum Provider: String, CaseIterable {
        case openai = "openai"
        case anthropic = "anthropic"
        case gemini = "gemini"
        case custom = "custom"

        var displayName: String {
            switch self {
            case .openai: return "OpenAI"
            case .anthropic: return "Anthropic"
            case .gemini: return "Google Gemini"
            case .custom: return "Custom"
            }
        }

        var baseURL: String {
            switch self {
            case .openai: return "https://api.openai.com/v1"
            case .anthropic: return "https://api.anthropic.com/v1"
            case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
            case .custom: return ""
            }
        }

        var apiKeyPlaceholder: String {
            switch self {
            case .openai: return "sk-..."
            case .anthropic: return "sk-ant-..."
            case .gemini: return "AI..."
            case .custom: return "Enter your API key"
            }
        }
    }

    // MARK: - Fetch Models

    func fetchModels(provider: Provider, apiKey: String) async throws -> [AIModel] {
        guard !apiKey.isEmpty else {
            throw AIModelError.noAPIKey
        }

        switch provider {
        case .openai:
            return try await fetchOpenAIModels(apiKey: apiKey)
        case .anthropic:
            return try await fetchAnthropicModels(apiKey: apiKey)
        case .gemini:
            return try await fetchGeminiModels(apiKey: apiKey)
        case .custom:
            return []
        }
    }

    // MARK: - OpenAI

    /// GET https://api.openai.com/v1/models
    private func fetchOpenAIModels(apiKey: String) async throws -> [AIModel] {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let result = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)

        // Filter to chat models, sorted by id
        let chatPrefixes = ["gpt-", "o1", "o3", "o4"]
        return result.data
            .filter { model in chatPrefixes.contains(where: { model.id.hasPrefix($0) }) }
            .filter { !$0.id.contains("realtime") && !$0.id.contains("audio") && !$0.id.contains("transcribe") && !$0.id.contains("tts") && !$0.id.contains("embedding") && !$0.id.contains("instruct") }
            .sorted { $0.id < $1.id }
            .map { AIModel(id: $0.id, name: $0.id) }
    }

    private struct OpenAIModelsResponse: Decodable {
        let data: [OpenAIModel]
    }

    private struct OpenAIModel: Decodable {
        let id: String
    }

    // MARK: - Anthropic

    /// GET https://api.anthropic.com/v1/models
    private func fetchAnthropicModels(apiKey: String) async throws -> [AIModel] {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=100")!)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let result = try JSONDecoder().decode(AnthropicModelsResponse.self, from: data)

        return result.data
            .sorted { $0.id > $1.id }
            .map { AIModel(id: $0.id, name: $0.displayName) }
    }

    private struct AnthropicModelsResponse: Decodable {
        let data: [AnthropicModel]
    }

    private struct AnthropicModel: Decodable {
        let id: String
        let displayName: String

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }

    // MARK: - Gemini

    /// GET https://generativelanguage.googleapis.com/v1beta/models?key=KEY
    private func fetchGeminiModels(apiKey: String) async throws -> [AIModel] {
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models")!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let result = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)

        // Filter to generateContent-capable models
        return result.models
            .filter { $0.supportedGenerationMethods.contains("generateContent") }
            .sorted { $0.name < $1.name }
            .map {
                let shortID = $0.name.replacingOccurrences(of: "models/", with: "")
                return AIModel(id: shortID, name: $0.displayName)
            }
    }

    private struct GeminiModelsResponse: Decodable {
        let models: [GeminiModel]
    }

    private struct GeminiModel: Decodable {
        let name: String
        let displayName: String
        let supportedGenerationMethods: [String]
    }

    // MARK: - Helpers

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AIModelError.invalidResponse
        }
        switch http.statusCode {
        case 200...299:
            return
        case 401:
            throw AIModelError.invalidAPIKey
        case 403:
            throw AIModelError.forbidden
        case 429:
            throw AIModelError.rateLimited
        default:
            throw AIModelError.httpError(http.statusCode)
        }
    }

    // MARK: - Errors

    enum AIModelError: LocalizedError {
        case noAPIKey
        case invalidAPIKey
        case forbidden
        case rateLimited
        case invalidResponse
        case httpError(Int)

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "Please enter an API key first."
            case .invalidAPIKey:
                return "Invalid API key. Please check and try again."
            case .forbidden:
                return "Access denied. Your API key may not have model listing permissions."
            case .rateLimited:
                return "Rate limited. Please wait a moment and try again."
            case .invalidResponse:
                return "Unexpected response from the server."
            case .httpError(let code):
                return "Server error (HTTP \(code))."
            }
        }
    }
}
