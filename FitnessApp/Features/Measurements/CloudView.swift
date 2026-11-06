import SwiftUI
import SwiftData
import Charts

/// Облак: вход, споделяне с треньор и (за треньора) преглед на клиентите.
struct CloudView: View {
    @Environment(\.modelContext) private var context
    @State private var cloud = CloudService.shared
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var message: String?
    @State private var working = false
    @State private var me: CloudProfile?
    @State private var clients: [CloudProfile] = []
    @State private var coachCode = ""
    @FocusState private var focus: LoginField?
    private enum LoginField { case email, password, name }

    var body: some View {
        Form {
            if cloud.isSignedIn {
                signedInSections
            } else {
                Section {
                    TextField("Имейл", text: $email)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                        .textContentType(.username)
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                    SecureField("Парола (поне 6 знака)", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.next)
                        .onSubmit { focus = .name }
                        .contentShape(Rectangle())
                        .onTapGesture { focus = .password }
                    TextField("Име (само при регистрация)", text: $name)
                        .focused($focus, equals: .name)
                        .submitLabel(.done)
                    Button("Влез") {
                        if let problem = loginProblem() { message = problem; return }
                        run { try await cloud.signIn(email: email.trimmed, password: password) }
                    }
                    Button("Регистрирай се") {
                        if let problem = loginProblem() { message = problem; return }
                        run { try await cloud.signUp(email: email.trimmed, password: password, name: name) }
                    }
                } header: {
                    Text("Вход")
                } footer: {
                    Text("Всеки (ти и клиентите) прави свой акаунт. Данните се качват, само когато си влязъл. Всеки нов акаунт автоматично се свързва с треньора, който вижда данните и имейла ти. Можеш да прекратиш връзката след вход.")
                }
            }

            if let message {
                Section { Text(message).font(.footnote) }
            }
        }
        .navigationTitle("Облак и треньор")
        .keyboardDoneButton()
        .task { if cloud.isSignedIn { await load() } }
        .disabled(working)
    }

    @ViewBuilder private var signedInSections: some View {
        Section {
            LabeledContent("Акаунт", value: cloud.email)
            if let last = cloud.lastUpload {
                LabeledContent("Последно качване", value: last.formatted(date: .abbreviated, time: .shortened))
            }
            Button("Качи данните сега") {
                run {
                    await cloud.syncIfNeeded(context: context, force: true)
                    message = cloud.lastUpload == nil ? "Неуспешно качване." : "Качено."
                }
            }
            Button("Изход", role: .destructive) { cloud.signOut(); me = nil; clients = [] }
        } header: {
            Text("Акаунт")
        } footer: {
            Text("Качват се тегло, мерки, тренировки, дневни калории/макроси и показатели от WHOOP/Health (последните 90–365 дни). Снимките не се качват.")
        }

        if let me {
            Section {
                if me.coach_id == nil {
                    LabeledContent("Моят код", value: me.code).font(.body.monospaced())
                    TextField("Код на треньора", text: $coachCode)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    Button("Свържи с треньор") {
                        run {
                            let ok = try await cloud.linkCoach(code: coachCode.trimmed)
                            message = ok ? "Свързан си с треньора." : "Няма такъв код."
                            await load()
                        }
                    }
                } else {
                    Text("Свързан си с треньор: той вижда данните ти.")
                    Button("Прекъсни връзката", role: .destructive) {
                        run { try await cloud.unlinkCoach(); await load() }
                    }
                }
            } header: {
                Text("Треньор")
            } footer: {
                if me.coach_id == nil {
                    Text("Дай своя код на треньора си или въведи неговия, за да го виждат твоите данни.")
                }
            }
        }

        Section {
            if clients.isEmpty {
                Text("Още няма клиенти. Клиентът въвежда твоя код в тази страница.").foregroundStyle(.secondary)
            }
            ForEach(clients) { client in
                NavigationLink(client.display_name.isEmpty ? "Клиент \(client.code)" : client.display_name) {
                    ClientDetailView(client: client)
                }
            }
        } header: {
            Text("Моите клиенти")
        }
    }

    private func loginProblem() -> String? {
        let e = email.trimmed
        if !e.contains("@") || !e.contains(".") { return "Въведи валиден имейл (напр. ime@gmail.com)." }
        if password.count < 6 { return "Паролата трябва да е поне 6 знака." }
        return nil
    }

    private func run(_ work: @escaping () async throws -> Void) {
        working = true
        message = nil
        Task {
            do {
                try await work()
                if cloud.isSignedIn, me == nil { await load() }
            } catch { message = error.localizedDescription }
            working = false
        }
    }

    private func load() async {
        do {
            let all = try await cloud.profiles()
            me = all.first { $0.id == cloud.userId }
            clients = all.filter { $0.coach_id == cloud.userId }
        } catch { message = error.localizedDescription }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Клиент

struct ClientDetailView: View {
    let client: CloudProfile
    @State private var snapshot: CloudSnapshot?
    @State private var updated = ""
    @State private var message: String?
    @State private var metricKey = "recovery"

    private static let metricKeys = ["recovery", "hrv", "rhr", "sleepHours", "steps", "strain"]

    var body: some View {
        List {
            if let message { Section { Text(message) } }
            if let s = snapshot {
                Section {
                    LabeledContent("Обновено", value: String(updated.prefix(16)).replacingOccurrences(of: "T", with: " "))
                    LabeledContent("Възраст / ръст", value: "\(s.age) г. / \(Int(s.heightCm)) см")
                    if let w = s.weights.last { LabeledContent("Последно тегло", value: "\(w.kg.formatted(.number.precision(.fractionLength(0...1)))) кг · \(w.d)") }
                }
                if s.weights.count > 1 {
                    Section("Тегло") { weightChart(s) }
                }
                Section("Показатели") {
                    Picker("Показател", selection: $metricKey) {
                        ForEach(Self.metricKeys, id: \.self) { Text(MetricKind(rawValue: $0)?.title ?? $0).tag($0) }
                    }
                    metricChart(s)
                }
                Section("Хранене (последни 14 дни)") {
                    let days = Array(s.food.suffix(14))
                    if days.isEmpty { Text("Няма данни").foregroundStyle(.secondary) }
                    ForEach(days.reversed(), id: \.d) { f in
                        LabeledContent(f.d, value: "\(Int(f.kcal)) ккал · Б \(Int(f.p)) В \(Int(f.c)) М \(Int(f.f))")
                            .font(.footnote)
                    }
                }
                Section("Тренировки") {
                    if s.workouts.isEmpty { Text("Няма данни").foregroundStyle(.secondary) }
                    ForEach(s.workouts.reversed().prefix(30)) { w in
                        DisclosureGroup {
                            ForEach(w.lifts, id: \.name) { lift in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(lift.name).font(.subheadline.weight(.semibold))
                                    Text(lift.sets.map { "\($0[0].formatted(.number.precision(.fractionLength(0...1))))×\($0[1].formatted(.number.precision(.fractionLength(0...1))))" }.joined(separator: "  "))
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        } label: {
                            VStack(alignment: .leading) {
                                Text("\(w.d) · \(w.title)")
                                Text("\(w.sets) серии · обем \(Int(w.volume)) кг").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else if message == nil {
                ProgressView()
            }
        }
        .navigationTitle(client.display_name.isEmpty ? "Клиент" : client.display_name)
        .task { await load() }
    }

    private func weightChart(_ s: CloudSnapshot) -> some View {
        let points = s.weights.compactMap { w in CloudDay.date(w.d).map { ($0, w.kg) } }
        return Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("Ден", p.0), y: .value("кг", p.1))
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartScrub(points.map { ScrubPoint(date: $0.0, value: $0.1, text: "\(scrubDate($0.0)): \($0.1.formatted(.number.precision(.fractionLength(0...1)))) кг") })
        .frame(height: 180)
    }

    private func metricChart(_ s: CloudSnapshot) -> some View {
        // При два източника за един ден се взема първият.
        var seen = Set<String>()
        let points: [(Date, Double)] = s.metrics.filter { $0.k == metricKey }.sorted { $0.d < $1.d }
            .filter { seen.insert($0.d).inserted }
            .compactMap { m in CloudDay.date(m.d).map { ($0, m.v) } }
        return Group {
            if points.isEmpty {
                Text("Няма данни").foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                        LineMark(x: .value("Ден", p.0), y: .value("Стойност", p.1))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartScrub(points.map { ScrubPoint(date: $0.0, value: $0.1, text: "\(scrubDate($0.0)): \(Int($0.1.rounded()))") })
                .frame(height: 160)
            }
        }
    }

    private func load() async {
        do {
            if let (data, time) = try await CloudService.shared.fetchSnapshot(of: client.id) {
                snapshot = data
                updated = time
            } else {
                message = "Клиентът още не е качил данни."
            }
        } catch { message = error.localizedDescription }
    }
}
