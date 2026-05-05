//
//  OpenAICompatibleChatAPI.swift
//  leanring-buddy
//
//  OpenAI-compatible streaming chat client for local/self-hosted models.
//  Targets `POST /v1/chat/completions` (OpenAI Chat Completions).
//

import Foundation

/// Streaming chat client that targets an OpenAI-compatible `POST /v1/chat/completions` endpoint.
/// Intended for local LLM servers (e.g. llama.cpp `llama-server`, Ollama OpenAI-compat, OpenRouter, etc.).
final class OpenAICompatibleChatAPI {
    private let chatCompletionsURL: URL
    private let session: URLSession
    var model: String
    private var apiKey: String?

    init(openAICompatibleBaseURL: String, apiKey: String?, model: String) {
        self.chatCompletionsURL = Self.makeChatCompletionsURL(openAICompatibleBaseURL: openAICompatibleBaseURL)
        self.apiKey = apiKey
        self.model = model

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        config.urlCache = nil
        config.httpCookieStorage = nil
        self.session = URLSession(configuration: config)
    }

    func setAPIKey(_ apiKey: String?) {
        self.apiKey = apiKey
    }

    struct ToolDefinition {
        let name: String
        let description: String?
        let parameters: [String: Any]
    }

    struct ToolCall: Decodable {
        struct FunctionCall: Decodable {
            let name: String
            let arguments: String
        }

        let id: String
        let type: String
        let function: FunctionCall
    }

    struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let role: String?
                let content: String?
                let tool_calls: [ToolCall]?
            }

            let message: Message
            let finish_reason: String?
        }

        let choices: [Choice]
    }

    func createChatCompletionNonStreaming(
        messages: [[String: Any]],
        tools: [ToolDefinition]?
    ) async throws -> ChatCompletionResponse.Choice.Message {
        var request = URLRequest(url: chatCompletionsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = [
            "model": model,
            "stream": false,
            "max_completion_tokens": 1200,
            "messages": messages,
        ]

        if let tools {
            body["tools"] = tools.map { tool in
                [
                    "type": "function",
                    "function": [
                        "name": tool.name,
                        "description": tool.description ?? "",
                        "parameters": tool.parameters,
                    ],
                ]
            }
            body["tool_choice"] = "auto"
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "OpenAICompatibleChatAPI", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid HTTP response",
            ])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let responseString = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "OpenAICompatibleChatAPI", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "API Error (\(httpResponse.statusCode)): \(responseString)",
            ])
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let firstChoice = decoded.choices.first else {
            throw NSError(domain: "OpenAICompatibleChatAPI", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Missing choices in response",
            ])
        }

        return firstChoice.message
    }

    /// Sends a vision/text request with streaming response. Calls `onTextChunk` with the full accumulated text so far.
    func analyzeImageStreaming(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)] = [],
        userPrompt: String,
        onTextChunk: @MainActor @Sendable (String) -> Void
    ) async throws -> (text: String, duration: TimeInterval) {
        let startTime = Date()

        var request = URLRequest(url: chatCompletionsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        if let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        var messages: [[String: Any]] = []
        messages.append([
            "role": "system",
            "content": systemPrompt
        ])

        for (userPlaceholder, assistantResponse) in conversationHistory {
            messages.append(["role": "user", "content": userPlaceholder])
            messages.append(["role": "assistant", "content": assistantResponse])
        }

        var contentBlocks: [[String: Any]] = []
        for image in images {
            contentBlocks.append([
                "type": "text",
                "text": image.label
            ])
            contentBlocks.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:\(detectImageMediaType(for: image.data));base64,\(image.data.base64EncodedString())"
                ]
            ])
        }
        contentBlocks.append([
            "type": "text",
            "text": userPrompt
        ])
        messages.append(["role": "user", "content": contentBlocks])

        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "max_completion_tokens": 800,
            "messages": messages
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = bodyData

        let (byteStream, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "OpenAICompatibleChatAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"]
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            var errorBodyChunks: [String] = []
            for try await line in byteStream.lines {
                errorBodyChunks.append(line)
            }
            let errorBody = errorBodyChunks.joined(separator: "\n")
            throw NSError(
                domain: "OpenAICompatibleChatAPI",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "API Error (\(httpResponse.statusCode)): \(errorBody)"]
            )
        }

        var accumulatedResponseText = ""

        for try await line in byteStream.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))

            guard jsonString != "[DONE]" else { break }

            guard let jsonData = jsonString.data(using: .utf8),
                  let eventPayload = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let choices = eventPayload["choices"] as? [[String: Any]],
                  let firstChoice = choices.first else {
                continue
            }

            if let delta = firstChoice["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                accumulatedResponseText += content
                let currentAccumulatedText = accumulatedResponseText
                await onTextChunk(currentAccumulatedText)
            }

            if let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String,
               accumulatedResponseText.isEmpty {
                accumulatedResponseText = content
                let currentAccumulatedText = accumulatedResponseText
                await onTextChunk(currentAccumulatedText)
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        return (text: accumulatedResponseText, duration: duration)
    }

    private static func makeChatCompletionsURL(openAICompatibleBaseURL: String) -> URL {
        let trimmedBaseURL = openAICompatibleBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)

        if let directURL = URL(string: trimmedBaseURL), directURL.path.contains("/v1/chat/completions") {
            return directURL
        }

        guard var urlComponents = URLComponents(string: trimmedBaseURL) else {
            return URL(string: "http://127.0.0.1:18081/v1/chat/completions")!
        }

        let basePath = urlComponents.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if basePath.isEmpty {
            urlComponents.path = "/v1/chat/completions"
        } else {
            urlComponents.path = "/" + basePath + "/v1/chat/completions"
        }

        return urlComponents.url ?? URL(string: "http://127.0.0.1:18081/v1/chat/completions")!
    }

    /// Detects the MIME type of image data by inspecting the first bytes.
    private func detectImageMediaType(for imageData: Data) -> String {
        if imageData.count >= 4 {
            let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
            let firstFourBytes = [UInt8](imageData.prefix(4))
            if firstFourBytes == pngSignature {
                return "image/png"
            }
        }
        return "image/jpeg"
    }
}
