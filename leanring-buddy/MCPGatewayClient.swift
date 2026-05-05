import Foundation

struct MCPToolDefinition: Decodable {
    let name: String
    let description: String?
    let inputSchema: [String: AnyCodable]
}

struct MCPToolsListResponse: Decodable {
    let tools: [MCPToolDefinition]
}

struct MCPJsonRpcResponse: Decodable {
    struct ErrorPayload: Decodable {
        let code: Int?
        let message: String?
    }

    struct ResultPayload: Decodable {
        struct ContentBlock: Decodable {
            let type: String?
            let text: String?
        }

        let content: [ContentBlock]?
    }

    let result: ResultPayload?
    let error: ErrorPayload?
}

final class MCPGatewayClient {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = true
        config.urlCache = nil
        config.httpCookieStorage = nil
        self.session = URLSession(configuration: config)
    }

    func listTools(mcpBaseURL: String, apiKey: String) async throws -> [MCPToolDefinition] {
        let url = try makeToolsListURL(mcpBaseURL: mcpBaseURL, apiKey: apiKey)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "MCPGatewayClient", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid HTTP response",
            ])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw NSError(domain: "MCPGatewayClient", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Tools list failed (HTTP \(httpResponse.statusCode)): \(body)",
            ])
        }

        // Some gateways return `{ tools: [...] }` and others return `[...]`.
        if let decoded = try? JSONDecoder().decode(MCPToolsListResponse.self, from: data) {
            return decoded.tools
        }
        if let decoded = try? JSONDecoder().decode([MCPToolDefinition].self, from: data) {
            return decoded
        }

        throw NSError(domain: "MCPGatewayClient", code: -2, userInfo: [
            NSLocalizedDescriptionKey: "Failed to decode tools list response.",
        ])
    }

    func callTool(
        mcpBaseURL: String,
        apiKey: String,
        toolName: String,
        arguments: [String: Any]
    ) async throws -> String {
        let url = try makeToolCallURL(mcpBaseURL: mcpBaseURL, apiKey: apiKey)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": "tools/call",
            "params": [
                "name": toolName,
                "arguments": arguments,
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "MCPGatewayClient", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid HTTP response",
            ])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw NSError(domain: "MCPGatewayClient", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Tool call failed (HTTP \(httpResponse.statusCode)): \(body)",
            ])
        }

        let decoded = try JSONDecoder().decode(MCPJsonRpcResponse.self, from: data)
        if let error = decoded.error {
            throw NSError(domain: "MCPGatewayClient", code: error.code ?? -1, userInfo: [
                NSLocalizedDescriptionKey: error.message ?? "MCP tool call failed.",
            ])
        }

        let blocks = decoded.result?.content ?? []
        let textBlocks = blocks.compactMap { block in
            if block.type == "text" { return block.text }
            return block.text
        }

        if !textBlocks.isEmpty {
            return textBlocks.joined(separator: "\n")
        }

        // Fallback: return raw JSON string so the model can still interpret.
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func makeToolsListURL(mcpBaseURL: String, apiKey: String) throws -> URL {
        let baseURL = try normalizeMcpBaseURL(mcpBaseURL)

        // Prefer the gateway's convenience list endpoint: <base>/tools?api_key=...
        var components = URLComponents(url: baseURL.appendingPathComponent("tools"), resolvingAgainstBaseURL: false)
        components?.queryItems = (components?.queryItems ?? []) + [URLQueryItem(name: "api_key", value: apiKey)]

        guard let url = components?.url else {
            throw NSError(domain: "MCPGatewayClient", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "Invalid tools list URL.",
            ])
        }
        return url
    }

    private func makeToolCallURL(mcpBaseURL: String, apiKey: String) throws -> URL {
        let baseURL = try normalizeMcpBaseURL(mcpBaseURL)

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = (components?.queryItems ?? []) + [URLQueryItem(name: "api_key", value: apiKey)]

        guard let url = components?.url else {
            throw NSError(domain: "MCPGatewayClient", code: -4, userInfo: [
                NSLocalizedDescriptionKey: "Invalid tool call URL.",
            ])
        }
        return url
    }

    private func normalizeMcpBaseURL(_ mcpBaseURL: String) throws -> URL {
        let trimmed = mcpBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            throw NSError(domain: "MCPGatewayClient", code: -5, userInfo: [
                NSLocalizedDescriptionKey: "Invalid MCP base URL.",
            ])
        }
        return url
    }
}

// MARK: - AnyCodable (minimal)

struct AnyCodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
            return
        }
        if let int = try? container.decode(Int.self) {
            value = int
            return
        }
        if let double = try? container.decode(Double.self) {
            value = double
            return
        }
        if let string = try? container.decode(String.self) {
            value = string
            return
        }
        if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
            return
        }
        if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
            return
        }
        value = NSNull()
    }
}

