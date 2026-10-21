import SwiftUI
import WebKit

struct PolarConnectView: View {
    @State private var polar = PolarService()
    @State private var showingLogin = false

    var body: some View {
        Form {
            Section {
                TextField("Client ID", text: $polar.clientId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Client Secret", text: $polar.clientSecret)
                TextField("Callback URL", text: $polar.redirectURI)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } header: {
                Text("Ключове от admin.polaraccesslink.com")
            } footer: {
                Text("Callback URL трябва да е същият като въведения при регистрацията на клиента. Ключовете се пазят само в защитеното хранилище на телефона.")
            }

            Section {
                if polar.isConnected {
                    Label("Свързано с Polar", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Button("Тествай и покажи данните") {
                        Task { await polar.runTest() }
                    }
                    Button("Изключи", role: .destructive) { polar.disconnect() }
                } else {
                    Button("Свържи с Polar") { showingLogin = true }
                        .disabled(!polar.hasKeys)
                }
                if polar.isBusy { ProgressView() }
                if let status = polar.statusText {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
            }

            if !polar.output.isEmpty {
                Section("Отговор от Polar") {
                    Text(polar.output)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                    Button("Копирай") { UIPasteboard.general.string = polar.output }
                }
            }
        }
        .navigationTitle("Polar Loop")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .sheet(isPresented: $showingLogin) {
            NavigationStack {
                if let url = polar.authorizationURL {
                    PolarLoginWebView(url: url, redirectURI: polar.redirectURI) { code, state in
                        showingLogin = false
                        Task { await polar.finishAuthorization(code: code, state: state) }
                    }
                    .navigationTitle("Polar")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Отказ") { showingLogin = false }
                        }
                    }
                }
            }
        }
    }
}

/// Уеб страница за вход в Polar. Прихваща пренасочването към callback адреса и взема кода от него.
struct PolarLoginWebView: UIViewRepresentable {
    let url: URL
    let redirectURI: String
    let onCode: (String, String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(redirectURI: redirectURI, onCode: onCode) }

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let redirectURI: String
        let onCode: (String, String?) -> Void

        init(redirectURI: String, onCode: @escaping (String, String?) -> Void) {
            self.redirectURI = redirectURI
            self.onCode = onCode
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url,
               Self.matchesRedirect(url, redirectURI: redirectURI),
               let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                decisionHandler(.cancel)
                let state = components.queryItems?.first(where: { $0.name == "state" })?.value
                onCode(code, state)
                return
            }
            decisionHandler(.allow)
        }

        private static func matchesRedirect(_ url: URL, redirectURI: String) -> Bool {
            guard let expected = URLComponents(string: redirectURI),
                  let actual = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
            return actual.scheme?.lowercased() == expected.scheme?.lowercased()
                && actual.host?.lowercased() == expected.host?.lowercased()
                && actual.port == expected.port
                && actual.path == expected.path
        }
    }
}
