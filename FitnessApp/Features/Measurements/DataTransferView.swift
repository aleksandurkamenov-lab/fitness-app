import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Резервно копие (JSON) и внос на тренировки от Strong/Hevy.
struct DataTransferView: View {
    @Environment(\.modelContext) private var context
    @State private var exportURL: URL?
    @State private var showImporter = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Сподели резервното копие", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button("Направи резервно копие (JSON)") {
                        do { exportURL = try DataTransfer.exportJSON(in: context) }
                        catch { message = error.localizedDescription }
                    }
                }
            } header: {
                Text("Експорт")
            } footer: {
                Text("Тегло, мерки и тренировки в един файл.")
            }

            Section {
                Button("Избери CSV файл") { showImporter = true }
            } header: {
                Text("Внос от Strong / Hevy")
            } footer: {
                Text("Експортирай CSV от другото приложение (в килограми). Повторен внос не дублира вече внесените тренировки. Нови упражнения се добавят с познатата по име мускулна група; поправи я в библиотеката, ако е грешна.")
            }

            if let message {
                Section { Text(message) }
            }
        }
        .navigationTitle("Данни")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let text = try String(contentsOf: url, encoding: .utf8)
                let count = try DataTransfer.importCSV(text, in: context)
                message = "Внесени тренировки: \(count)"
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
