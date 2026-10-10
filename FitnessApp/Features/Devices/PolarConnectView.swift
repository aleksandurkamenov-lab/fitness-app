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
                    PolarLoginWebView(url: url, redirectPrefix: polar.redirectURI) { code in
                        showingLogin = false
                        Task { await polar.finishAuthorization(code: code) }
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
    let redirectPrefix: String
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(redirectPrefix: redirectPrefix, onCode: onCode) }

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let redirectPrefix: String
        let onCode: (String) -> Void

        init(redirectPrefix: String, onCode: @escaping (String) -> Void) {
            self.redirectPrefix = redirectPrefix
            self.onCode = onCode
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url,
               url.absoluteString.hasPrefix(redirectPrefix),
               let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                   .queryItems?.first(where: { $0.name == "code" })?.value {
                decisionHandler(.cancel)
                onCode(code)
                return
            }
            decisionHandler(.allow)
        }
    }
}
