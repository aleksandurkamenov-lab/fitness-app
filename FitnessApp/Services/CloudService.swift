import Foundation
import SwiftData
import Observation

// MARK: - Снимка на данните (качва се в облака, треньорът я чете)

struct CloudSnapshot: Codable, Sendable {
    struct Weight: Codable, Sendable { var d: String; var kg: Double; var bf: Double? }
    struct Measure: Codable, Sendable { var d: String; var k: String; var cm: Double; var flex: Bool; var side: String }
    struct Lift: Codable, Sendable { var name: String; var sets: [[Double]] }
    struct Workout: Codable, Sendable, Identifiable {
        var d: String; var title: String; var volume: Double; var sets: Int; var lifts: [Lift]
        var id: String { d + title }
    }
    struct Food: Codable, Sendable { var d: String; var kcal: Double; var p: Double; var c: Double; var f: Double }
    struct Metric: Codable, Sendable { var d: String; var k: String; var v: Double; var s: String }

    var name: String = ""
    var sex: String = ""
    var age: Int = 0
    var heightCm: Double = 0
    var goal: String = ""
    var weights: [Weight] = []
    var measures: [Measure] = []
    var workouts: [Workout] = []
    var food: [Food] = []
    var metrics: [Metric] = []
}

struct CloudProfile: Codable, Sendable, Identifiable {
    var id: String
    var display_name: String
    var code: String
    var coach_id: String?
}

enum CloudDay {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    static func string(_ date: Date) -> String { formatter.string(from: date) }
    static func date(_ text: String) -> Date? { formatter.date(from: text) }
}

enum CloudError: LocalizedError {
    case notConfigured, notSignedIn, server(String)
    var errorDescription: String? {
        switch self {
        case .notConfigured: "Въведи адрес и ключ на Supabase."
        case .notSignedIn: "Не си влязъл."
        case .server(let text): text
        }
    }
}

// MARK: - Услуга

@MainActor
@Observable
final class CloudService {
    static let shared = CloudService()

    var urlText: String = Keychain.get("cloud.url") ?? "https://zdhdvxslolwelbpezjvp.supabase.co" { didSet { Keychain.set(urlText, for: "cloud.url") } }
    var keyText: String = Keychain.get("cloud.key") ?? "sb_publishable_y8Ztcv8gr3fkLRWbv2Hfdg_BWj9r5UQ" { didSet { Keychain.set(keyText, for: "cloud.key") } }
    var email: String = Keychain.get("cloud.email") ?? ""
    private(set) var userId: String = Keychain.get("cloud.uid") ?? ""
    var lastUpload: Date? = UserDefaults.standard.object(forKey: "cloud.lastUpload") as? Date
    var busy = false

    var isSignedIn: Bool { !userId.isEmpty && Keychain.get("cloud.refresh") != nil }
    private var base: URL? { URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))) }
    private var key: String { keyText.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: Вход

    private struct AuthResponse: Decodable {
        struct User: Decodable { let id: String }
        let access_token: String?
        let refresh_token: String?
        let user: User?
    }

    func signUp(email: String, password: String, name: String) async throws {
        let body: [String: Any] = ["email": email, "password": password, "data": ["name": name]]
        let data = try await raw("/auth/v1/signup", method: "POST", body: body, token: nil)
        try store(data, email: email)
    }

    func signIn(email: String, password: String) async throws {
        let body: [String: Any] = ["email": email, "password": password]
        let data = try await raw("/auth/v1/token?grant_type=password", method: "POST", body: body, token: nil)
        try store(data, email: email)
    }

    func signOut() {
        for k in ["cloud.access", "cloud.refresh", "cloud.uid", "cloud.email"] { Keychain.set("", for: k) }
        userId = ""
        email = ""
    }

    private func store(_ data: Data, email: String) throws {
        let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
        guard let access = auth.access_token, let refresh = auth.refresh_token, let user = auth.user else {
            throw CloudError.server("Регистрацията е приета, но Supabase иска потвърждение на имейла. Изключи „Confirm email“ (виж инструкциите).")
        }
        Keychain.set(access, for: "cloud.access")
        Keychain.set(refresh, for: "cloud.refresh")
        Keychain.set(user.id, for: "cloud.uid")
        Keychain.set(email, for: "cloud.email")
        userId = user.id
        self.email = email
    }

    private func refresh() async throws {
        guard let token = Keychain.get("cloud.refresh") else { throw CloudError.notSignedIn }
        let data = try await raw("/auth/v1/token?grant_type=refresh_token", method: "POST", body: ["refresh_token": token], token: nil)
        try store(data, email: email)
    }

    // MARK: HTTP

    private func raw(_ path: String, method: String, body: Any?, token: String?, extra: [String: String] = [:]) async throws -> Data {
        guard let base, !key.isEmpty, let url = URL(string: base.absoluteString + path) else { throw CloudError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue(key, forHTTPHeaderField: "apikey")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in extra { request.setValue(v, forHTTPHeaderField: k) }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            if code == 401 { throw CloudError.notSignedIn }
            let text = String(data: data, encoding: .utf8) ?? ""
            throw CloudError.server("Грешка \(code): \(text.prefix(200))")
        }
        return data
    }

    /// Заявка с токен; при изтекъл токен го подновява веднъж.
    private func authed(_ path: String, method: String = "GET", body: Any? = nil, extra: [String: String] = [:]) async throws -> Data {
        guard isSignedIn else { throw CloudError.notSignedIn }
        do {
            return try await raw(path, method: method, body: body, token: Keychain.get("cloud.access"), extra: extra)
        } catch CloudError.notSignedIn {
            try await refresh()
            return try await raw(path, method: method, body: body, token: Keychain.get("cloud.access"), extra: extra)
        }
    }

    // MARK: Данни

    func uploadSnapshot(_ snapshot: CloudSnapshot) async throws {
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot))
        let row: [String: Any] = ["user_id": userId, "updated_at": ISO8601DateFormatter().string(from: .now), "data": json]
        _ = try await authed("/rest/v1/snapshots?on_conflict=user_id", method: "POST", body: [row],
                             extra: ["Prefer": "resolution=merge-duplicates,return=minimal"])
        lastUpload = .now
        UserDefaults.standard.set(lastUpload, forKey: "cloud.lastUpload")
    }

    /// Качва снимка, ако е минал поне час (или принудително).
    func syncIfNeeded(context: ModelContext, force: Bool = false) async {
        guard isSignedIn, !busy else { return }
        if !force, let lastUpload, Date.now.timeIntervalSince(lastUpload) < 3600 { return }
        busy = true
        defer { busy = false }
        do { try await uploadSnapshot(CloudSnapshotBuilder.build(context: context, name: email)) } catch {}
    }

    /// Моят профил и профилите на клиентите ми.
    func profiles() async throws -> [CloudProfile] {
        let data = try await authed("/rest/v1/profiles?select=id,display_name,code,coach_id")
        return try JSONDecoder().decode([CloudProfile].self, from: data)
    }

    func linkCoach(code: String) async throws -> Bool {
        let data = try await authed("/rest/v1/rpc/link_coach", method: "POST", body: ["c": code])
        return (try? JSONDecoder().decode(Bool.self, from: data)) ?? false
    }

    func unlinkCoach() async throws {
        _ = try await authed("/rest/v1/rpc/unlink_coach", method: "POST", body: [String: String]())
    }

    func setName(_ name: String) async throws {
        _ = try await authed("/rest/v1/profiles?id=eq.\(userId)", method: "PATCH", body: ["display_name": name])
    }

    private struct SnapshotRow: Decodable {
        let updated_at: String
        let data: CloudSnapshot
    }

    func fetchSnapshot(of clientId: String) async throws -> (CloudSnapshot, String)? {
        let data = try await authed("/rest/v1/snapshots?user_id=eq.\(clientId)&select=updated_at,data")
        guard let row = try JSONDecoder().decode([SnapshotRow].self, from: data).first else { return nil }
        return (row.data, row.updated_at)
    }
}

// MARK: - Изграждане на снимката от локалната база

@MainActor
enum CloudSnapshotBuilder {
    static func build(context: ModelContext, name: String) -> CloudSnapshot {
        var snap = CloudSnapshot()
        snap.name = name
        let cal = Calendar.current
        let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
        if let profile {
            snap.sex = profile.sexRaw
            snap.age = profile.age
            snap.heightCm = profile.heightCm
            snap.goal = profile.goalRaw
        }
        let since90 = cal.date(byAdding: .day, value: -90, to: .now) ?? .now
        let since180 = cal.date(byAdding: .day, value: -180, to: .now) ?? .now
        let since365 = cal.date(byAdding: .day, value: -365, to: .now) ?? .now

        let weights = (try? context.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date)]))) ?? []
        snap.weights = weights.filter { $0.date >= since365 }
            .map { .init(d: CloudDay.string($0.date), kg: $0.kg, bf: $0.bodyFatPercent) }

        let measures = (try? context.fetch(FetchDescriptor<MeasurementEntry>(sortBy: [SortDescriptor(\.date)]))) ?? []
        snap.measures = measures.filter { $0.date >= since365 }
            .map { .init(d: CloudDay.string($0.date), k: $0.kindRaw, cm: $0.cm, flex: $0.isFlexed, side: $0.sideRaw) }

        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date)]))) ?? []
        for session in sessions where session.date >= since180 {
            let work = session.sets.filter(\.isWorkSet)
            guard !work.isEmpty else { continue }
            var lifts: [CloudSnapshot.Lift] = []
            for group in session.exerciseGroups {
                let rows = group.sets.filter(\.isWorkSet).map { [$0.weight, $0.repsValue] }
                if !rows.isEmpty { lifts.append(.init(name: group.exercise?.name ?? "?", sets: rows)) }
            }
            snap.workouts.append(.init(d: CloudDay.string(session.date), title: session.title,
                                       volume: WorkoutMath.totalVolume(session.sets), sets: work.count, lifts: lifts))
        }

        let food = (try? context.fetch(FetchDescriptor<FoodEntry>())) ?? []
        var byDay: [String: CloudSnapshot.Food] = [:]
        for entry in food where entry.date >= since90 {
            let d = CloudDay.string(entry.date)
            var day = byDay[d] ?? .init(d: d, kcal: 0, p: 0, c: 0, f: 0)
            day.kcal += entry.kcal
            day.p += entry.protein
            day.c += entry.carbs
            day.f += entry.fat
            byDay[d] = day
        }
        snap.food = byDay.values.sorted { $0.d < $1.d }

        let metrics = (try? context.fetch(FetchDescriptor<DailyMetric>())) ?? []
        snap.metrics = metrics.filter { $0.day >= since90 }
            .map { .init(d: CloudDay.string($0.day), k: $0.kindRaw, v: $0.value, s: $0.sourceRaw) }
        return snap
    }
}
