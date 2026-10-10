import SwiftUI

struct WhoopConnectView: View {
    @State private var whoop = WhoopService.shared
    @State private var showingLogin = false

    var body: some View {
        Form {
            Section {
                TextField("Client ID", text: $whoop.clientId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Client Secret", text: $whoop.clientSecret)
                TextField("Redirect URL", text: $whoop.redirectURI)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } header: {
                Text("Ключове от developer-dashboard.whoop.com")
            } footer: {
                Text("Redirect URL трябва да е същият като въведения в таблото на WHOOP за приложението. Ключовете се пазят само в защитеното хранилище на телефона.")
            }

            Section {
                if whoop.isConnected {
                    Label("Свързано с WHOOP", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Button("Обнови данните") { Task { await whoop.load() } }
                    Button("Изключи", role: .destructive) { whoop.disconnect() }
                } else {
                    Button("Свържи с WHOOP") { showingLogin = true }
                        .disabled(!whoop.hasKeys)
                }
                if whoop.isBusy { ProgressView() }
                if let status = whoop.statusText {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
            }

            if let s = whoop.snapshot {
                Section("Последни данни") {
                    LabeledContent("Recovery", value: s.recoveryScore.map { "\(Int($0))%" } ?? "–")
                    LabeledContent("HRV", value: s.hrv.map { "\(Int($0)) мс" } ?? "–")
                    LabeledContent("Пулс в покой", value: s.rhr.map { "\(Int($0))" } ?? "–")
                    LabeledContent("Сън (performance)", value: s.sleepPerformance.map { "\(Int($0))%" } ?? "–")
                    LabeledContent("Strain", value: s.strain.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "–")
                }
            }
        }
        .navigationTitle("WHOOP")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .task { if whoop.isConnected { await whoop.load() } }
        .sheet(isPresented: $showingLogin) {
            NavigationStack {
                if let url = whoop.authorizationURL {
                    PolarLoginWebView(url: url, redirectPrefix: whoop.redirectURI) { code in
                        showingLogin = false
                        Task {
                            await whoop.finishAuthorization(code: code)
                            await whoop.load()
                        }
                    }
                    .navigationTitle("WHOOP")
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
