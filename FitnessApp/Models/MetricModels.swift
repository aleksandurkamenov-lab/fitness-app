import Foundation
import SwiftData

/// Показатели, за които пазим дневна история и рисуваме графики.
enum MetricKind: String, CaseIterable, Identifiable {
    case recovery, sleepPerformance, sleepHours, hrv, rhr, respiratory, spo2, strain, steps, activeKcal, skinTemp

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
