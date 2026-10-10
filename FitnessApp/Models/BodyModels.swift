import Foundation
import SwiftData

enum Sex: String, CaseIterable, Identifiable, Codable {
    case male, female
    var id: String { rawValue }
    var title: String { self == .male ? "Мъж" : "Жена" }
}

enum GoalKind: String, CaseIterable, Identifiable, Codable {
    case lose, maintain, gain
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lose: "Сваляне"
        case .maintain: "Поддръжка"
        case .gain: "Качване"
        }
    }
}

enum MeasurementKind: String, CaseIterable, Identifiable, Codable {
    case waist, abdomen, neck, chest, arm, thigh, calf, hips
    var id: String { rawValue }
    var title: String {
        switch self {
        case .waist: "Талия (под пъпа)"
        case .abdomen: "Корем"
        case .neck: "Врат"
        case .chest: "Гърди"
        case .arm: "Ръка"
        case .thigh: "Бедро"
        case .calf: "Прасец"
        case .hips: "Ханш"
        }
    }

    /// За тези мускулни зони се мери и отпуснато, и стегнато.
    var supportsFlex: Bool {
        switch self {
        case .arm, .thigh, .calf, .abdomen: true
        default: false
        }
    }
}

/// Профилът на потребителя: от него се смятат калкулаторите.
@Model
final class UserProfile {
    var sexRaw: String = Sex.male.rawValue
    var birthDate: Date = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    var heightCm: Double = 175
    var activityFactor: Double = 1.55
    var goalRaw: String = GoalKind.maintain.rawValue
    /// Желано темпо в кг на седмица (0.1 / 0.5 / 1).
    var weeklyRateKg: Double = 0.5
    /// Темпо на сваляне и на качване се пазят отделно (кг на седмица).
    var lossRateKg: Double = 0.5
    var gainRateKg: Double = 0.5
    /// Белтък в г на кг тегло: при дефицит и при бълк/поддръжка.
    var proteinLoseGPerKg: Double = 2.0
    var proteinOtherGPerKg: Double = 1.8
    /// Минимум мазнини в г на кг тегло.
    var fatMinGPerKg: Double = 0.8

    init() {}

    var sex: Sex {
        get { Sex(rawValue: sexRaw) ?? .male }
        set { sexRaw = newValue.rawValue }
    }

    var goal: GoalKind {
        get { GoalKind(rawValue: goalRaw) ?? .maintain }
        set { goalRaw = newValue.rawValue }
    }

    var age: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 0
    }
}

@Model
final class WeightEntry {
    var date: Date = Date.now
    var kg: Double = 0
    /// % мазнини, ако идва от кантар (по избор).
    var bodyFatPercent: Double?

    init(date: Date = .now, kg: Double, bodyFatPercent: Double? = nil) {
        self.date = date
        self.kg = kg
        self.bodyFatPercent = bodyFatPercent
    }
}

@Model
final class MeasurementEntry {
    var date: Date = Date.now
    var kindRaw: String = MeasurementKind.waist.rawValue
    var cm: Double = 0
    /// true = стегнато, false = отпуснато.
    var isFlexed: Bool = false

    init(date: Date = .now, kind: MeasurementKind, cm: Double, isFlexed: Bool = false) {
        self.date = date
        self.kindRaw = kind.rawValue
        self.cm = cm
        self.isFlexed = isFlexed
    }

    var kind: MeasurementKind { MeasurementKind(rawValue: kindRaw) ?? .waist }
}
