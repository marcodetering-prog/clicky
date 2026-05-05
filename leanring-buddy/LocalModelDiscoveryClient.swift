import Foundation

@MainActor
final class LocalModelDiscoveryClient {
    struct OllamaTagsResponse: Decodable {
        struct Model: Decodable {
            let name: String
        }

        let models: [Model]
    }

    struct OpenAIModelsResponse: Decodable {
        struct Model: Decodable {
            let id: String
        }

        let data: [Model]
    }

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = true
        config.urlCache = nil
        config.httpCookieStorage = nil
        self.session = URLSession(configuration: config)
    }

    func listModelIDs(openAICompatibleBaseURL: String, apiKey: String?) async throws -> [String] {
        let rootBaseURL = try normalizeRootBaseURL(openAICompatibleBaseURL)

        var modelIDs: [String] = []

        // Prefer Ollama tags if available.
        if let ollamaTagsURL = URL(string: "api/tags", relativeTo: rootBaseURL) {
            var request = URLRequest(url: ollamaTagsURL)
            request.httpMethod = "GET"

            if let (data, httpResponse) = try? await dataWithHTTPResponse(for: request),
               (200...299).contains(httpResponse.statusCode),
               let decoded = try? JSONDecoder().decode(OllamaTagsResponse.self, from: data) {
                modelIDs.append(contentsOf: decoded.models.map(\.name))
            }
        }

        // Also try OpenAI models endpoint.
        if let openAIModelsURL = URL(string: "v1/models", relativeTo: rootBaseURL) {
            var request = URLRequest(url: openAIModelsURL)
            request.httpMethod = "GET"

            if let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }

            if let (data, httpResponse) = try? await dataWithHTTPResponse(for: request),
               (200...299).contains(httpResponse.statusCode),
               let decoded = try? JSONDecoder().decode(OpenAIModelsResponse.self, from: data) {
                modelIDs.append(contentsOf: decoded.data.map(\.id))
            }
        }

        let normalized = modelIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Stable ordering, deduped.
        let uniqueSorted = Array(Set(normalized)).sorted { $0.lowercased() < $1.lowercased() }
        return uniqueSorted
    }

    private func dataWithHTTPResponse(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "LocalModelDiscoveryClient", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid HTTP response",
            ])
        }
        return (data, httpResponse)
    }

    private func normalizeRootBaseURL(_ openAICompatibleBaseURL: String) throws -> URL {
        let trimmed = openAICompatibleBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            throw NSError(domain: "LocalModelDiscoveryClient", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Invalid base URL.",
            ])
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw NSError(domain: "LocalModelDiscoveryClient", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "Invalid base URL components.",
            ])
        }

        // If user pastes a full OpenAI endpoint, drop the path.
        components.path = ""
        components.query = nil
        components.fragment = nil

        guard let rootURL = components.url else {
            throw NSError(domain: "LocalModelDiscoveryClient", code: -4, userInfo: [
                NSLocalizedDescriptionKey: "Invalid normalized base URL.",
            ])
        }

        return rootURL
    }
}

