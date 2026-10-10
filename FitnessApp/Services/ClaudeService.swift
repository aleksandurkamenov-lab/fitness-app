import Foundation

enum AIModel: String, CaseIterable, Identifiable {
    case haiku = "claude-haiku-5-5"
    case sonnet = "claude-sonnet-5-5"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .haiku: "Haiku (бърз, евтин)"
        case .sonnet: "Sonnet (по-умен, по-скъп)"
        }
    }
}

struct ClaudeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Заявки към Claude Messages API. Ключът стои в Keychain на телефона.
enum ClaudeService {
    static let keyName = "anthropicApiKey"

    static var apiKey: String { Keychain.get(keyName) ?? "" }

    static func send(model: String, system: String, messages: [[String: Any]],
                     tools: [[String: Any]]) async throws -> (content: [[String: Any]], stopReason: String) {
        let key = apiKey.filter { !$0.isWhitespace }
        guard !key.isEmpty else {
            throw ClaudeError(message: "Няма API ключ. Въведи го от зъбчатото колело горе вдясно.")
        }
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw ClaudeError(message: "Грешен адрес.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2000,
            "system": system,
            "messages": messages,
            "tools": tools,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let detail = ((json["error"] as? [String: Any])?["message"] as? String)
                ?? String(data: data, encoding: .utf8) ?? ""
            switch status {
            case 401: throw ClaudeError(message: "Грешен API ключ (401). Провери го в настройките.")
            case 429: throw ClaudeError(message: "Твърде много заявки, опитай след минута.")
            case 503, 529: throw ClaudeError(message: "Claude е претоварен, опитай пак след малко.")
            default: throw ClaudeError(message: "Грешка \(status): \(detail)")
            }
        }
        let content = (json["content"] as? [[String: Any]]) ?? []
        let stop = (json["stop_reason"] as? String) ?? ""
        return (content, stop)
    }
}
