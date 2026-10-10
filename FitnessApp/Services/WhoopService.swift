import Foundation
import Observation

// MARK: Модели на отговорите на WHOOP API v2 (само полетата, които ползваме)

private struct WhoopPage<T: Decodable>: Decodable {
    let records: [T]
    let next_token: String?
}

private struct WhoopRecovery: Decodable {
    struct Score: Decodable {
        let recovery_score: Double?
        let resting_heart_rate: Double?
        let hrv_rmssd_milli: Double?
        let spo2_percentage: Double?
        let skin_temp_celsius: Double?
        let user_calibrating: Bool?
    }
    let created_at: String?
    let score_state: String?
    let score: Score?
}

private struct WhoopSleep: Decodable {
    struct Stage: Decodable {
        let total_in_bed_time_milli: Double?
        let total_light_sleep_time_milli: Double?
        let total_slow_wave_sleep_time_milli: Double?
        let total_rem_sleep_time_milli: Double?
    }
    struct Score: Decodable {
        let stage_summary: Stage?
        let respiratory_rate: Double?
        let sleep_performance_percentage: Double?
        let sleep_efficiency_percentage: Double?
    }
    let start: String?
    let end: String?
    let nap: Bool?
    let score_state: String?
    let score: Score?
}

private struct WhoopCycle: Decodable {
    struct Score: Decodable {
        let strain: Double?
        let kilojoule: Double?
        let average_heart_rate: Double?
    }
    let start: String?
    let score_state: String?
    let score: Score?
}

private struct WhoopWorkout: Decodable {
    struct Score: Decodable {
        let strain: Double?
        let kilojoule: Double?
    }
    let start: String?
    let end: String?
    let sport_name: String?
    let score_state: String?
    let score: Score?
}

/// Данните от WHOOP за последния ден.
struct WhoopSnapshot {
    var recoveryScore: Double?
    var rhr: Double?
    var hrv: Double?
    var spo2: Double?
    var skinTemp: Double?
    /// Отклонение на температурата на кожата от последните дни.
    var skinTempDelta: Double?
    var respiratory: Double?
    var sleepPerformance: Double?
    var asleepHours: Double?
    var inBedHours: Double?
    var sleepStart: Date?
    var sleepEnd: Date?
    var strain: Double?
    var cycleKcal: Double?
    var isCalibrating = false
    var workouts: [WorkoutInfo] = []
    var hrvBaseline: RecoveryMath.Baseline?
    var rhrBaseline: RecoveryMath.Baseline?
    var respiratoryBaseline: RecoveryMath.Baseline?
    var spo2Baseline: RecoveryMath.Baseline?
}

/// Връзка с WHOOP API v2 (OAuth2). Ключовете и токените се пазят в Keychain.
@Observable
final class WhoopService {
    /// Един общ екземпляр: WHOOP сменя токена при всяко обновяване и два екземпляра биха се счупили един друг.
    static let shared = WhoopService()

    private let authURL = "https://api.prod.whoop.com/oauth/oauth2/auth"
    private let tokenURL = "https://api.prod.whoop.com/oauth/oauth2/token"
    private let apiBase = "https://api.prod.whoop.com/developer"
    private let scopes = "read:recovery read:sleep read:cycles read:workout read:profile read:body_measurement offline"

    var clientId: String { didSet { Keychain.set(clientId, for: "whoop.clientId") } }
    var clientSecret: String { didSet { Keychain.set(clientSecret, for: "whoop.clientSecret") } }
    var redirectURI: String { didSet { UserDefaults.standard.set(redirectURI, forKey: "whoop.redirectURI") } }
    private var accessToken: String?
    private var refreshToken: String?
    private var expiry: Date?
    private var refreshTask: Task<Bool, Never>?
    private var lastTokenStatus = 0
    var statusText: String?
    var snapshot: WhoopSnapshot?
    var isBusy = false

    var isConnected: Bool { refreshToken != nil || accessToken != nil }
    private var cleanId: String { clientId.filter { !$0.isWhitespace } }
    private var cleanSecret: String { clientSecret.filter { !$0.isWhitespace } }
    var hasKeys: Bool { !clientId.isEmpty && !clientSecret.isEmpty }

    init() {
        clientId = Keychain.get("whoop.clientId") ?? ""
        clientSecret = Keychain.get("whoop.clientSecret") ?? ""
        redirectURI = UserDefaults.standard.string(forKey: "whoop.redirectURI") ?? "fitnessapp://whoop/callback"
        accessToken = Keychain.get("whoop.accessToken")
        refreshToken = Keychain.get("whoop.refreshToken")
        expiry = (UserDefaults.standard.object(forKey: "whoop.expiry") as? Date)
    }

    var authorizationURL: URL? {
        let state = String((0..<8).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
        var components = URLComponents(string: authURL)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: cleanId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "state", value: state),
        ]
        return components?.url
    }

    func disconnect() {
        accessToken = nil
        refreshToken = nil
        expiry = nil
        snapshot = nil
        for key in ["whoop.accessToken", "whoop.refreshToken"] { Keychain.set("", for: key) }
        UserDefaults.standard.removeObject(forKey: "whoop.expiry")
        statusText = "Изключено от WHOOP."
    }

    // MARK: Вход и токени

    func finishAuthorization(code: String) async {
        isBusy = true
        defer { isBusy = false }
        statusText = "Свързвам…"
        let fields = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": cleanId,
            "client_secret": cleanSecret,
            "redirect_uri": redirectURI,
        ]
        // WHOOP изисква данните за вход в тялото на заявката (client_secret_post).
        if await requestToken(form: fields, basicAuth: false) { return }
        statusText = (statusText ?? "") + "\n(ID \(cleanId.count) знака, ключ \(cleanSecret.count) знака)"
    }

    private func requestToken(form: [String: String], basicAuth: Bool) async -> Bool {
        guard let url = URL(string: tokenURL) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if basicAuth {
            let basic = Data("\(cleanId):\(cleanSecret)".utf8).base64EncodedString()
            request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let body = form.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)
        return await handleTokenResponse(request)
    }

    /// Само едно обновяване наведнъж: WHOOP сменя refresh токена при всяко обновяване,
    /// а паралелните заявки със стария токен могат да развалят връзката.
    private func refreshAccessToken() async -> Bool {
        if let refreshTask { return await refreshTask.value }
        let task = Task { await performRefresh() }
        refreshTask = task
        let ok = await task.value
        refreshTask = nil
        return ok
    }

    private func performRefresh() async -> Bool {
        guard let refreshToken else { return false }
        // Като при входа: form-urlencoded с ключовете в тялото (client_secret_post).
        let ok = await requestToken(form: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": cleanId,
            "client_secret": cleanSecret,
            "scope": "offline",
        ], basicAuth: false)
        if !ok && (lastTokenStatus == 400 || lastTokenStatus == 401) {
            disconnect()
            statusText = "Връзката с WHOOP изтече. Натисни „Свържи с WHOOP“ отново, ключовете са запазени."
        }
        return ok
    }

    private func handleTokenResponse(_ request: URLRequest) async -> Bool {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            lastTokenStatus = status
            guard status == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["access_token"] as? String else {
                statusText = "WHOOP отказа токена (код \(status)): \(String(data: data, encoding: .utf8)?.prefix(300) ?? "")"
                return false
            }
            accessToken = token
            Keychain.set(token, for: "whoop.accessToken")
            if let refresh = json["refresh_token"] as? String {
                refreshToken = refresh
                Keychain.set(refresh, for: "whoop.refreshToken")
            }
            let seconds = (json["expires_in"] as? Double) ?? 3600
            expiry = Date.now.addingTimeInterval(seconds)
            UserDefaults.standard.set(expiry, forKey: "whoop.expiry")
            statusText = "Свързано с WHOOP."
            return true
        } catch {
            statusText = "Грешка: \(error.localizedDescription)"
            return false
        }
    }

    private func validToken() async -> String? {
        if let accessToken, let expiry, expiry > .now.addingTimeInterval(60) { return accessToken }
        if await refreshAccessToken() { return accessToken }
        return nil
    }

    // MARK: Данни

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:], as type: T.Type) async -> T? {
        guard let token = await validToken(),
              var components = URLComponents(string: apiBase + path) else { return nil }
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                statusText = "WHOOP върна код \(status) за \(path)"
                return nil
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            statusText = "Не успях да прочета \(path): \(error.localizedDescription)"
            return nil
        }
    }

    private static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    func load() async {
        guard isConnected, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        async let recoveries = get("/v2/recovery", query: ["limit": "25"], as: WhoopPage<WhoopRecovery>.self)
        async let sleeps = get("/v2/activity/sleep", query: ["limit": "25"], as: WhoopPage<WhoopSleep>.self)
        async let cycles = get("/v2/cycle", query: ["limit": "3"], as: WhoopPage<WhoopCycle>.self)
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let iso = ISO8601DateFormatter()
        async let workouts = get("/v2/activity/workout",
                                 query: ["limit": "25", "start": iso.string(from: startOfDay)],
                                 as: WhoopPage<WhoopWorkout>.self)

        var result = WhoopSnapshot()
        let recoveryRecords = (await recoveries)?.records ?? []
        let sleepRecords = ((await sleeps)?.records ?? []).filter { ($0.nap ?? false) == false }

        if let latest = recoveryRecords.first(where: { $0.score_state == "SCORED" }), let score = latest.score {
            result.recoveryScore = score.recovery_score
            result.rhr = score.resting_heart_rate
            result.hrv = score.hrv_rmssd_milli
            result.spo2 = score.spo2_percentage
            result.skinTemp = score.skin_temp_celsius
            result.isCalibrating = score.user_calibrating ?? false
        }
        let scoredRecoveries = recoveryRecords.compactMap(\.score)
        result.hrvBaseline = RecoveryMath.Baseline(values: scoredRecoveries.compactMap(\.hrv_rmssd_milli))
        result.rhrBaseline = RecoveryMath.Baseline(values: scoredRecoveries.compactMap(\.resting_heart_rate))
        result.spo2Baseline = RecoveryMath.Baseline(values: scoredRecoveries.compactMap(\.spo2_percentage))
        let skin = scoredRecoveries.compactMap(\.skin_temp_celsius)
        if let latestSkin = skin.first, skin.count > 3 {
            let rest = skin.dropFirst()
            result.skinTempDelta = latestSkin - rest.reduce(0, +) / Double(rest.count)
        }

        let scoredSleeps = sleepRecords.filter { $0.score_state == "SCORED" }
        if let latest = scoredSleeps.first, let score = latest.score {
            result.sleepPerformance = score.sleep_performance_percentage
            result.respiratory = score.respiratory_rate
            if let stage = score.stage_summary {
                let asleep = (stage.total_light_sleep_time_milli ?? 0)
                    + (stage.total_slow_wave_sleep_time_milli ?? 0)
                    + (stage.total_rem_sleep_time_milli ?? 0)
                result.asleepHours = asleep / 3_600_000
                result.inBedHours = stage.total_in_bed_time_milli.map { $0 / 3_600_000 }
            }
            result.sleepStart = Self.date(latest.start)
            result.sleepEnd = Self.date(latest.end)
        }
        result.respiratoryBaseline = RecoveryMath.Baseline(
            values: scoredSleeps.compactMap { $0.score?.respiratory_rate })

        if let cycle = ((await cycles)?.records ?? []).first, let score = cycle.score {
            result.strain = score.strain
            result.cycleKcal = score.kilojoule.map { $0 / 4.184 }
        }

        result.workouts = ((await workouts)?.records ?? []).compactMap { workout in
            guard let start = Self.date(workout.start), let end = Self.date(workout.end) else { return nil }
            return WorkoutInfo(name: workout.sport_name?.capitalized ?? "Тренировка",
                               start: start,
                               minutes: end.timeIntervalSince(start) / 60,
                               kcal: workout.score?.kilojoule.map { $0 / 4.184 })
        }

        if result.recoveryScore != nil || result.sleepPerformance != nil || result.strain != nil {
            statusText = "Свързано с WHOOP."
        }
        snapshot = result
    }

    // MARK: История

    /// Всички страници на колекция (до `pages` по 25 записа).
    private func allRecords<T: Decodable>(_ path: String, pages: Int, as type: T.Type) async -> [T] {
        var result: [T] = []
        var token: String?
        for _ in 0..<pages {
            var query = ["limit": "25"]
            if let token { query["nextToken"] = token }
            guard let page = await get(path, query: query, as: WhoopPage<T>.self) else { break }
            result += page.records
            guard let next = page.next_token, !next.isEmpty else { break }
            token = next
        }
        return result
    }

    /// Дневна история от WHOOP за около 100 дни.
    func history() async -> [MetricPoint] {
        guard isConnected else { return [] }
        var points: [MetricPoint] = []
        func add(_ kind: MetricKind, _ date: Date?, _ value: Double?) {
            guard let date, let value else { return }
            points.append(MetricPoint(kind: kind, day: HistorySync.dayStart(date), value: value, source: .whoop))
        }

        for record in await allRecords("/v2/recovery", pages: 4, as: WhoopRecovery.self)
        where record.score_state == "SCORED" {
            let day = Self.date(record.created_at)
            add(.recovery, day, record.score?.recovery_score)
            add(.hrv, day, record.score?.hrv_rmssd_milli)
            add(.rhr, day, record.score?.resting_heart_rate)
            add(.spo2, day, record.score?.spo2_percentage)
            add(.skinTemp, day, record.score?.skin_temp_celsius)
        }
        for record in await allRecords("/v2/activity/sleep", pages: 4, as: WhoopSleep.self)
        where record.score_state == "SCORED" && (record.nap ?? false) == false {
            let day = Self.date(record.end)
            add(.sleepPerformance, day, record.score?.sleep_performance_percentage)
            add(.respiratory, day, record.score?.respiratory_rate)
            if let stage = record.score?.stage_summary {
                let asleep = (stage.total_light_sleep_time_milli ?? 0)
                    + (stage.total_slow_wave_sleep_time_milli ?? 0)
                    + (stage.total_rem_sleep_time_milli ?? 0)
                if asleep > 0 { add(.sleepHours, day, asleep / 3_600_000) }
            }
        }
        for record in await allRecords("/v2/cycle", pages: 4, as: WhoopCycle.self)
        where record.score_state == "SCORED" {
            add(.strain, Self.date(record.start), record.score?.strain)
        }
        return points
    }
}
