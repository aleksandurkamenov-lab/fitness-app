import Foundation

/// Калкулатори за тяло и хранене. Всички стойности са ориентировъчни, не са медицински съвет.
enum BodyMath {
    static func bmi(kg: Double, cm: Double) -> Double? {
        guard kg > 0, cm > 0 else { return nil }
        let m = cm / 100
        return kg / (m * m)
    }

    /// % мазнини по US Navy (в см).
    static func navyBodyFat(sex: Sex, heightCm: Double, waist: Double, neck: Double, hips: Double?) -> Double? {
        guard heightCm > 0, waist > neck, neck > 0 else { return nil }
        let value: Double
        switch sex {
        case .male:
            value = 495 / (1.0324 - 0.19077 * log10(waist - neck) + 0.15456 * log10(heightCm)) - 450
        case .female:
            guard let hips, hips > 0, waist + hips > neck else { return nil }
            value = 495 / (1.29579 - 0.35004 * log10(waist + hips - neck) + 0.22100 * log10(heightCm)) - 450
        }
        return value > 0 && value < 70 ? value : nil
    }

    /// Relative Fat Mass: 64 − 20 × (ръст / талия) за мъже, 76 − ... за жени.
    static func rfm(sex: Sex, heightCm: Double, waist: Double) -> Double? {
        guard heightCm > 0, waist > 0 else { return nil }
        let base: Double = sex == .male ? 64 : 76
        let value = base - 20 * heightCm / waist
        return value > 0 && value < 70 ? value : nil
    }

    /// Базален метаболизъм по Mifflin-St Jeor (ккал/ден).
    static func bmr(sex: Sex, kg: Double, cm: Double, age: Int) -> Double {
        let base = 10 * kg + 6.25 * cm - 5 * Double(age)
        return sex == .male ? base + 5 : base - 161
    }

    static func tdee(bmr: Double, activity: Double) -> Double { bmr * activity }

    struct Targets {
        var kcal: Double
        var protein: Double
        var fat: Double
        var carbs: Double
    }

    /// Калории и макроси. 1 кг телесна маса ≈ 7700 ккал.
    static func targets(profile: UserProfile, kg: Double) -> Targets? {
        guard kg > 0 else { return nil }
        let bmr = bmr(sex: profile.sex, kg: kg, cm: profile.heightCm, age: profile.age)
        let maintenance = tdee(bmr: bmr, activity: profile.activityFactor)
        let daily = profile.weeklyRateKg * 7700 / 7
        let kcal: Double
        switch profile.goal {
        case .lose: kcal = maintenance - daily
        case .maintain: kcal = maintenance
        case .gain: kcal = maintenance + daily
        }
        let protein = (profile.goal == .lose ? 2.0 : 1.8) * kg
        let fat = max(0.8 * kg, 0.25 * kcal / 9)
        let carbs = max(0, (kcal - protein * 4 - fat * 9) / 4)
        return Targets(kcal: kcal, protein: protein, fat: fat, carbs: carbs)
    }

    struct TrendPoint: Identifiable {
        let date: Date
        let kg: Double
        let trend: Double
        var id: Date { date }
    }

    /// 7-дневна пълзяща средна на теглото.
    static func trend(_ entries: [WeightEntry]) -> [TrendPoint] {
        let sorted = entries.sorted { $0.date < $1.date }
        return sorted.map { entry in
            let from = entry.date.addingTimeInterval(-6 * 86_400)
            let window = sorted.filter { $0.date >= from && $0.date <= entry.date }
            let avg = window.reduce(0) { $0 + $1.kg } / Double(max(window.count, 1))
            return TrendPoint(date: entry.date, kg: entry.kg, trend: avg)
        }
    }
}
