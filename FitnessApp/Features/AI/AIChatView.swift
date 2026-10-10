import SwiftUI
import SwiftData
import UIKit

/// Чат с Claude: въпроси, съвети като личен треньор и бързо записване на храна и тегло.
struct AIChatView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AIMessage.date) private var messages: [AIMessage]
    @AppStorage("aiModel") private var model = AIModel.haiku.rawValue
    @State private var input = ""
    @State private var shareItems: ShareItems?
    @State private var busy = false
    @State private var errorText: String?
    @State private var showingSettings = false
    @State private var health = HealthService()
    @State private var healthDays: [Date: NutritionDay] = [:]
    @FocusState private var focused: Bool

    @AppStorage("lastWeeklyAnalysis") private var lastWeeklyAnalysis = 0.0

    private let weeklyPrompt = "Седмичен анализ (снимки, кг, мерки, тренировки, обем)"

    private var weeklyDue: Bool {
        Date.now.timeIntervalSince1970 - lastWeeklyAnalysis > 7 * 86_400
    }

    private let quickPrompts = [
        "Съвет за днес",
        "Какво да хапна за оставащите макроси?",
        "Обобщи седмицата",
        "Как върви прогресът ми?",
        "Как е възстановяването ми?",
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if messages.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        if ClaudeService.apiKey.isEmpty {
                            Text("Без API ключ бутоните и съобщенията отварят Claude приложението с твоите данни (влиза в Pro плана). Избери Claude от менюто за споделяне. Текстът се копира и в клипборда, ако трябва да го поставиш.")
                        } else {
                            Text("Питай каквото искаш или пиши какво си ял, например „200 г ориз и 150 г пилешко на обяд“, и аз ще го запиша.")
                        }
                        Text("Виждам теглото, храненето, тренировките, съня и възстановяването ти. Съветите са ориентировъчни, не са медицински съвет.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
                ForEach(messages) { message in
                    MessageBubble(message: message)
                }
                if busy {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Мисля…").foregroundStyle(.secondary)
                    }
                }
                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if weeklyDue && !busy {
                    Button {
                        send(weeklyPrompt, withPhotos: true)
                    } label: {
                        Label("Време е за седмичния анализ", systemImage: "chart.line.uptrend.xyaxis")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                }
                if input.isEmpty && !busy {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            if !weeklyDue {
                                Button("Седмичен анализ") { send(weeklyPrompt, withPhotos: true) }
                                    .buttonStyle(.bordered)
                                    .font(.footnote)
                            }
                            ForEach(quickPrompts, id: \.self) { prompt in
                                Button(prompt) { send(prompt) }
                                    .buttonStyle(.bordered)
                                    .font(.footnote)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Съобщение", text: $input, axis: .vertical)
                        .lineLimit(1...5)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                    Button {
                        send(input)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                    }
                    .disabled(busy || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
            .background(.bar)
        }
        .navigationTitle("AI треньор")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Настройки", systemImage: "gearshape")
                    }
                    Button(role: .destructive) {
                        for message in messages { context.delete(message) }
                        try? context.save()
                    } label: {
                        Label("Изчисти чата", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(item: $shareItems) { share in
            ActivityView(items: share.items)
        }
        .sheet(isPresented: $showingSettings) {
            AISettingsView(model: $model)
        }
        .task {
            healthDays = await health.nutrition(days: 14)
        }
    }

    private func send(_ text: String, withPhotos: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !busy else { return }
        input = ""
        if ClaudeService.apiKey.isEmpty {
            shareToClaudeApp(trimmed, withPhotos: withPhotos)
            return
        }
        errorText = nil
        context.insert(AIMessage(role: "user", text: trimmed))
        try? context.save()
        busy = true
        Task {
            do {
                let history = (try? context.fetch(FetchDescriptor<AIMessage>(sortBy: [SortDescriptor(\.date)]))) ?? []
                let images = withPhotos ? AIAssistant.weeklyPhotos(context: context) : []
                let result = try await AIAssistant.run(history: history, model: model, context: context,
                                                       healthDays: healthDays, images: images)
                if withPhotos { lastWeeklyAnalysis = Date.now.timeIntervalSince1970 }
                if !result.reply.isEmpty {
                    context.insert(AIMessage(role: "assistant", text: result.reply))
                }
                try? context.save()
            } catch {
                errorText = error.localizedDescription
            }
            busy = false
        }
    }
}

extension AIChatView {
    /// Без API ключ: данните (и снимките) отиват в Claude приложението през менюто за споделяне.
    private func shareToClaudeApp(_ task: String, withPhotos: Bool) {
        let photos = withPhotos ? AIAssistant.weeklyPhotos(context: context) : []
        let text = AIAssistant.exportText(task: task, context: context, healthDays: healthDays,
                                          photoLabels: photos.map(\.label))
        UIPasteboard.general.string = text
        var items: [Any] = [text]
        for photo in photos {
            if let image = UIImage(data: photo.data) { items.append(image) }
        }
        shareItems = ShareItems(items: items)
        if withPhotos { lastWeeklyAnalysis = Date.now.timeIntervalSince1970 }
    }
}

struct ShareItems: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct MessageBubble: View {
    let message: AIMessage

    private var attributed: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: message.text, options: options)) ?? AttributedString(message.text)
    }

    var body: some View {
        switch message.role {
        case "user":
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .padding(10)
                    .background(Color.accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 14))
            }
        case "action":
            Label(message.text, systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.green)
        default:
            Text(attributed)
                .textSelection(.enabled)
                .padding(10)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                .padding(.trailing, 24)
        }
    }
}

private struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var model: String
    @State private var key = ""
    @State private var savedLength = ClaudeService.apiKey.count

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-...", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Запази ключа") {
                        let clean = key.filter { !$0.isWhitespace }
                        Keychain.set(clean, for: ClaudeService.keyName)
                        savedLength = clean.count
                        key = ""
                    }
                    .disabled(key.isEmpty)
                } header: {
                    Text("Claude API ключ")
                } footer: {
                    Text(savedLength > 0 ? "Има запазен ключ (\(savedLength) знака). Пази се само на телефона." :
                            "Направи ключ в console.anthropic.com → API Keys и го постави тук. Плаща се отделно от Claude Pro, с предплатени кредити.")
                }

                Section {
                    Picker("Модел", selection: $model) {
                        ForEach(AIModel.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                } footer: {
                    Text("Haiku стига за записване и бързи въпроси. Sonnet дава по-добри анализи, но струва няколко пъти повече.")
                }

                Section {
                    Link("Отвори console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                }
            }
            .navigationTitle("AI настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
