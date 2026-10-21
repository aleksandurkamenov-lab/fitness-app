import Foundation
import Observation

/// Връзка с Polar AccessLink API v3 (OAuth2). Тайните ключове се пазят в Keychain.
@Observable
final class PolarService {
    private let apiBase = "https://www.polaraccesslink.com"

    var clientId: String { didSet { Keychain.set(clientId, for: "polar.clientId") } }
    var clientSecret: String { didSet { Keychain.set(clientSecret, for: "polar.clientSecret") } }
    var redirectURI: String {
        didSet { UserDefaults.standard.set(redirectURI, forKey: "polar.redirectURI") }
    }
    private(set) var accessToken: String?
    private(set) var polarUserId: String?
    private var pendingOAuthState: String?
    var statusText: String?
    var output: String = ""
    var isBusy = false

    var isConnected: Bool { accessToken != nil }
    var hasKeys: Bool { !clientId.isEmpty && !clientSecret.isEmpty }

    init() {
        clientId = Keychain.get("polar.clientId") ?? ""
        clientSecret = Keychain.get("polar.clientSecret") ?? ""
        redirectURI = UserDefaults.standard.string(forKey: "polar.redirectURI") ?? "http://localhost/callback"
        accessToken = Keychain.get("polar.accessToken")
        polarUserId = Keychain.get("polar.userId")
    }

    var authorizationURL: URL? {
        if pendingOAuthState == nil {
            pendingOAuthState = UUID().uuidString
        }
        var components = URLComponents(string: "https://flow.polar.com/oauth2/authorization")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "accesslink.read_all"),
            URLQueryItem(name: "state", value: pendingOAuthState),
        ]
        return components?.url
    }

    func disconnect() {
        accessToken = nil
        polarUserId = nil
        Keychain.set("", for: "polar.accessToken")
        Keychain.set("", for: "polar.userId")
        statusText = "Изключено от Polar."
        output = ""
    }

    // MARK: Вход

    /// Размяна на кода от Polar за токен, после регистрация на потребителя (изисква се еднократно).
    func finishAuthorization(code: String, state: String?) async {
        guard let expectedState = pendingOAuthState, state == expectedState else {
            pendingOAuthState = nil
            statusText = "Входът в Polar не беше потвърден. Опитай отново."
            return
        }
        pendingOAuthState = nil
        isBusy = true
        defer { isBusy = false }
        statusText = "Свързвам…"
        guard let url = URL(string: "https://polarremote.com/v2/oauth2/token") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let basic = Data("\(clientId):\(clientSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["access_token"] as? String else {
                statusText = "Polar отказа обмена на кода (код \(status)): \(String(data: data, encoding: .utf8) ?? "")"
                return
            }
            accessToken = token
            Keychain.set(token, for: "polar.accessToken")
            if let id = json["x_user_id"] {
                polarUserId = "\(id)"
                Keychain.set("\(id)", for: "polar.userId")
            }
            await registerUser()
        } catch {
            statusText = "Грешка при свързване: \(error.localizedDescription)"
        }
    }

    private func registerUser() async {
        guard let token = accessToken, let url = URL(string: "\(apiBase)/v3/users") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["member-id": "fitness-\(polarUserId ?? "me")"])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200, 409:
                statusText = "Свързано с Polar."
            case 403:
                statusText = "Polar иска да приемеш условията им във Polar Flow (профил → Settings), после опитай пак."
            default:
                statusText = "Регистрацията върна код \(status): \(String(data: data, encoding: .utf8) ?? "")"
            }
        } catch {
            statusText = "Грешка при регистрация: \(error.localizedDescription)"
        }
    }

    // MARK: Данни

    /// Сурова заявка (за проверка какво връща Polar): връща красиво форматиран отговор.
    func fetchRaw(_ path: String) async -> String {
        guard let token = accessToken, let url = URL(string: apiBase + path) else { return "Няма връзка." }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            var body = String(data: data, encoding: .utf8) ?? ""
            if let object = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
               let text = String(data: pretty, encoding: .utf8) {
                body = text
            }
            return "GET \(path)\nКод: \(status)\n\(body.prefix(6000))"
        } catch {
            return "GET \(path)\nГрешка: \(error.localizedDescription)"
        }
    }

    func runTest() async {
        isBusy = true
        defer { isBusy = false }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let today = formatter.string(from: .now)
        var parts: [String] = []
        for path in [
            "/v3/users/nightly-recharge",
            "/v3/users/sleep",
            "/v3/users/activities/\(today)",
            "/v3/users/continuous-heart-rate/\(today)",
        ] {
            parts.append(await fetchRaw(path))
        }
        output = parts.joined(separator: "\n\n")
    }
}
