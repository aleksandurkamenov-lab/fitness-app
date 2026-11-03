import Foundation
import SwiftData

/// Показатели, за които пазим дневна история и рисуваме графики.
enum MetricKind: String, CaseIterable, Identifiable {
    case recovery, sleepPerformance, sleepHours, hrv, rhr, respiratory, spo2, strain, steps, activeKcal, skinTemp, workoutMinutes, strengthSessions, cardioSessions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recovery: "Възстановяване"
        case .sleepPerformance: "Сън (оценка)"
        case .sleepHours: "Сън (часове)"
        case .hrv: "HRV"
        case .rhr: "Пулс в покой"
        case .respiratory: "Дишане"
        case .spo2: "SpO₂"
        case .strain: "Натоварване"
        case .steps: "Крачки"
        case .activeKcal: "Активни калории"
        case .skinTemp: "Температура на кожата"
        case .workoutMinutes: "Тренировки и кардио"
        case .strengthSessions: "Силови сесии"
        case .cardioSessions: "Кардио сесии"
        }
    }

    var unit: String {
        switch self {
        case .recovery, .sleepPerformance, .spo2: "%"
        case .sleepHours: "ч"
        case .hrv: "мс"
        case .rhr: "уд./мин"
        case .respiratory: "вд./мин"
        case .strain: ""
        case .steps: ""
        case .activeKcal: "ккал"
        case .skinTemp: "°C"
        case .workoutMinutes: "мин"
        case .strengthSessions, .cardioSessions: ""
        }
    }

    var digits: Int {
        switch self {
        case .sleepHours, .respiratory, .strain, .skinTemp: 1
        default: 0
        }
    }

    /// Крачките и калориите са по-точни от часовника/телефона (Health), останалото от WHOOP.
    var preferHealth: Bool { self == .steps || self == .activeKcal }
}

/// Силова или кардио сесия: по името на спорта; непознатите и по-късите от 35 мин са кардио, останалите силови.
enum SessionKindRule {
    static func isStrength(sport: String?, minutes: Double) -> Bool {
        let name = (sport ?? "").lowercased()
        let strength = ["weight", "strength", "powerlift", "functional", "crossfit", "gym", "силов"]
        if strength.contains(where: { name.contains($0) }) { return true }
        let cardio = ["run", "walk", "cycl", "bik", "swim", "row", "elliptic", "hiit", "cardio", "stair", "hik", "ski", "spin", "jog", "dance", "boxing", "kickbox", "treadmill", "assault"]
        if cardio.contains(where: { name.contains($0) }) { return false }
        return minutes >= 35
    }
}

enum MetricSource: String {
    case whoop, health
}

/// Една дневна стойност на показател от даден източник.
@Model
final class DailyMetric {
    var day: Date = Date.now
    var kindRaw: String = ""
    var value: Double = 0
    var sourceRaw: String = MetricSource.health.rawValue

    init(day: Date, kind: MetricKind, value: Double, source: MetricSource) {
        self.day = day
        self.kindRaw = kind.rawValue
        self.value = value
        self.sourceRaw = source.rawValue
    }

    var kind: MetricKind? { MetricKind(rawValue: kindRaw) }
}

struct MetricPoint {
    let kind: MetricKind
    let day: Date
    let value: Double
    let source: MetricSource
}

struct DayValue: Identifiable {
    let day: Date
    let value: Double
    var id: Date { day }
}

enum TrendTarget: Hashable {
    case metric(MetricKind)
    case weight

    var title: String {
        switch self {
        case .metric(let kind): kind.title
        case .weight: "Тегло"
        }
    }
}

enum MetricSeries {
    /// Една стойност на ден от предпочитания източник (иначе от другия) в интервала [from, to).
    static func series(_ kind: MetricKind, in metrics: [DailyMetric], from: Date, to: Date = .distantFuture) -> [DayValue] {
        let preferred: MetricSource = kind.preferHealth ? .health : .whoop
        var byDay: [Date: (value: Double, preferred: Bool)] = [:]
        for metric in metrics where metric.kindRaw == kind.rawValue && metric.day >= from && metric.day < to {
            let isPreferred = metric.sourceRaw == preferred.rawValue
            if let current = byDay[metric.day], current.preferred, !isPreferred { continue }
            byDay[metric.day] = (metric.value, isPreferred)
        }
        return byDay.map { DayValue(day: $0.key, value: $0.value.value) }.sorted { $0.day < $1.day }
    }
}
