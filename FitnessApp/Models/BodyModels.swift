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

    /// Мерят се отделно за лява и дясна страна.
    var supportsSides: Bool {
        switch self {
        case .arm, .thigh, .calf: true
        default: false
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
    /// Оценка на % мазнини (0 = няма) и откъде е; ползва се за BMR по постната маса.
    var bodyFatPercent: Double = 0
    var bodyFatSource: String = ""
    /// Ръчно зададен % мазнини (0 = автоматично); има предимство пред оценката.
    var manualBodyFat: Double = 0
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
    /// Ръчно зададени макроси в грамове; 0 = автоматично.
    var customProteinG: Double = 0
    var customFatG: Double = 0
    var customCarbsG: Double = 0
    /// Средни крачки на ден и кардио минути на седмица (ръчно, докато не идват от Health).
    var avgDailySteps: Double = 8000
    var weeklyCardioMinutes: Double = 0
    /// Променлив прием: повече калории (от въглехидрати) в тренировъчни дни, по-малко в почивни; седмичната сума е същата.
    var variableCalories: Bool = false
    var trainingDaysPerWeek: Int = 4
    /// С колко % над средното са тренировъчните дни.
    var trainingDayBoostPercent: Double = 10

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
    /// Идентификатор на записа в Apple Health (празен за ръчни записи).
    var healthId: String = ""

    init(date: Date = .now, kg: Double, bodyFatPercent: Double? = nil, healthId: String = "") {
        self.date = date
        self.kg = kg
        self.bodyFatPercent = bodyFatPercent
        self.healthId = healthId
    }
}

@Model
final class MeasurementEntry {
    var date: Date = Date.now
    var kindRaw: String = MeasurementKind.waist.rawValue
    var cm: Double = 0
    /// true = стегнато, false = отпуснато.
    var isFlexed: Bool = false
    /// "left", "right" или празно, когато не е важно.
    var sideRaw: String = ""

    init(date: Date = .now, kind: MeasurementKind, cm: Double, isFlexed: Bool = false, side: String = "") {
        self.date = date
        self.kindRaw = kind.rawValue
        self.cm = cm
        self.isFlexed = isFlexed
        self.sideRaw = side
    }

    var kind: MeasurementKind { MeasurementKind(rawValue: kindRaw) ?? .waist }
}
