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

    /// Базален метаболизъм (ккал/ден): Katch-McArdle по постната маса, когато е известен % мазнини, иначе Mifflin-St Jeor.
    static func bmr(sex: Sex, kg: Double, cm: Double, age: Int, bodyFat: Double = 0) -> Double {
        if bodyFat >= 4 && bodyFat <= 55 {
            return 370 + 21.6 * kg * (1 - bodyFat / 100)
        }
        let base = 10 * kg + 6.25 * cm - 5 * Double(age)
        return sex == .male ? base + 5 : base - 161
    }

    /// Най-добра оценка на % мазнини: ръчно зададен, иначе средно от US Navy (врат, корем) и RFM (корем, ръст), иначе кантар (неточен).
    static func bodyFatEstimate(profile: UserProfile, weights: [WeightEntry],
                                measurements: [MeasurementEntry]) -> (percent: Double, source: String)? {
        if profile.manualBodyFat >= 4 { return (profile.manualBodyFat, "ръчно") }
        func latest(_ kind: MeasurementKind) -> Double? {
            measurements.sorted { $0.date < $1.date }.last { $0.kind == kind && !$0.isFlexed && $0.cm > 0 }?.cm
        }
        if let waist = latest(.abdomen) ?? latest(.waist) {
            let navy = latest(.neck).flatMap {
                navyBodyFat(sex: profile.sex, heightCm: profile.heightCm, waist: waist, neck: $0, hips: latest(.hips))
            }
            let relative = rfm(sex: profile.sex, heightCm: profile.heightCm, waist: waist)
            // И двете формули са по обиколки, не по ИТМ, затова не надуват мазнините при мускулести хора; средното ги изглажда.
            switch (navy, relative) {
            case let (n?, r?): return ((n + r) / 2, "US Navy + RFM")
            case let (n?, nil): return (n, "US Navy")
            case let (nil, r?): return (r, "RFM")
            default: break
            }
        }
        let cutoff = Date.now.addingTimeInterval(-30 * 86_400)
        if let scale = weights.last(where: { $0.date >= cutoff && ($0.bodyFatPercent ?? 0) > 0 })?.bodyFatPercent {
            return (scale, "кантар")
        }
        return nil
    }

    /// Записва оценката в профила, за да я ползват калкулаторите за разход.
    static func refreshBodyFat(profile: UserProfile, weights: [WeightEntry], measurements: [MeasurementEntry]) {
        let estimate = bodyFatEstimate(profile: profile, weights: weights, measurements: measurements)
        let percent = estimate?.percent ?? 0
        let source = estimate?.source ?? ""
        if abs(profile.bodyFatPercent - percent) > 0.01 { profile.bodyFatPercent = percent }
        if profile.bodyFatSource != source { profile.bodyFatSource = source }
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
        let bmr = bmr(sex: profile.sex, kg: kg, cm: profile.heightCm, age: profile.age, bodyFat: profile.bodyFatPercent)
        let maintenance = tdee(bmr: bmr, activity: profile.activityFactor)
        let rate = profile.goal == .lose ? profile.lossRateKg : profile.gainRateKg
        let daily = rate * 7700 / 7
        let kcal: Double
        switch profile.goal {
        case .lose: kcal = maintenance - daily
        case .maintain: kcal = maintenance
        case .gain: kcal = maintenance + daily
        }
        let protein = (profile.goal == .lose ? profile.proteinLoseGPerKg : profile.proteinOtherGPerKg) * kg
        let fat = max(profile.fatMinGPerKg * kg, 0.25 * kcal / 9)
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
        var result: [TrendPoint] = []
        result.reserveCapacity(sorted.count)
        var start = 0
        var sum = 0.0
        for (index, entry) in sorted.enumerated() {
            sum += entry.kg
            let from = entry.date.addingTimeInterval(-6 * 86_400)
            while start < index && sorted[start].date < from {
                sum -= sorted[start].kg
                start += 1
            }
            let count = Double(max(index - start + 1, 1))
            result.append(TrendPoint(date: entry.date, kg: entry.kg, trend: sum / count))
        }
        return result
    }

    // MARK: Прогноза

    /// Приблизителни ккал от тренировки със силови тежести (MET ≈ 5) за последните 28 дни, на седмица.
    static func trainingKcalPerWeek(sessions: [WorkoutSession], kg: Double) -> (kcal: Double, perWeek: Double) {
        let from = Date.now.addingTimeInterval(-28 * 86_400)
        let recent = sessions.filter { $0.isFinished && $0.date >= from }
        guard !recent.isEmpty else { return (0, 0) }
        let minutes = recent.reduce(0.0) { total, session in
            let end = session.finishedAt ?? session.date
            return total + min(max(end.timeIntervalSince(session.date) / 60, 20), 150)
        }
        let kcal = 5 * 3.5 * kg / 200 * minutes
        return (kcal / 4, Double(recent.count) / 4)
    }

    /// Енергиен баланс за днес до този момент.
    struct DayEnergy {
        var basal: Double
        var active: Double
        var total: Double
        var intake: Double
        var fromWhoop: Bool
        /// Базов обмен за целия ден (24 ч).
        var fullDayBasal: Double = 0
        /// Очакван разход за целия ден: до сега + остатъкът от базовия обмен.
        var projectedTotal: Double = 0
        var balance: Double { intake - total }
    }

    /// Разход за деня до момента: при WHOOP е общата енергия на цикъла, иначе базов обмен (пропорционално на изминалата част от деня) + активни калории от Health.
    static func dayEnergy(profile: UserProfile, kg: Double, intake: Double, activeKcal: Double?,
                          whoopTotal: Double?, now: Date = .now) -> DayEnergy {
        let daily = bmr(sex: profile.sex, kg: kg, cm: profile.heightCm, age: profile.age, bodyFat: profile.bodyFatPercent)
        let startOfDay = Calendar.current.startOfDay(for: now)
        let fraction = min(max(now.timeIntervalSince(startOfDay) / 86_400, 0), 1)
        let basal = daily * fraction
        let active = activeKcal ?? 0
        if let whoopTotal, whoopTotal > 0 {
            return DayEnergy(basal: max(whoopTotal - active, 0), active: active, total: whoopTotal, intake: intake, fromWhoop: true,
                             fullDayBasal: daily, projectedTotal: whoopTotal + daily * (1 - fraction))
        }
        return DayEnergy(basal: basal, active: active, total: basal + active, intake: intake, fromWhoop: false,
                         fullDayBasal: daily, projectedTotal: daily + active)
    }

    struct Forecast {
        var intake: Double
        var expenditure: Double
        var baseKcal: Double
        var stepsKcal: Double
        var trainingKcal: Double
        var cardioKcal: Double
        var weeklyChangeKg: Double
    }

    /// Прогноза: приемът от макросите срещу приблизителния разход.
    static func forecast(profile: UserProfile, kg: Double, intake: Double, sessions: [WorkoutSession]) -> Forecast {
        let bmr = bmr(sex: profile.sex, kg: kg, cm: profile.heightCm, age: profile.age, bodyFat: profile.bodyFatPercent)
        let base = bmr * 1.15
        let steps = profile.avgDailySteps * 0.00044 * kg
        let training = trainingKcalPerWeek(sessions: sessions, kg: kg).kcal / 7
        let cardio = profile.weeklyCardioMinutes * 6 * 3.5 * kg / 200 / 7
        let expenditure = base + steps + training + cardio
        return Forecast(intake: intake, expenditure: expenditure, baseKcal: base, stepsKcal: steps,
                        trainingKcal: training, cardioKcal: cardio,
                        weeklyChangeKg: (intake - expenditure) * 7 / 7700)
    }

    /// Реален наклон на теглото (кг на седмица) от последните 21 дни, ако има достатъчно данни.
    static func actualWeeklyChange(_ entries: [WeightEntry]) -> Double? {
        let from = Date.now.addingTimeInterval(-21 * 86_400)
        let points = entries.filter { $0.date >= from }.sorted { $0.date < $1.date }
        guard points.count >= 4,
              let first = points.first, let last = points.last,
              last.date.timeIntervalSince(first.date) >= 7 * 86_400 else { return nil }
        let xs = points.map { $0.date.timeIntervalSince(first.date) / 86_400 }
        let ys = points.map(\.kg)
        let n = Double(points.count)
        let sumX = xs.reduce(0, +), sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let sumXX = xs.reduce(0) { $0 + $1 * $1 }
        let denominator = n * sumXX - sumX * sumX
        guard denominator != 0 else { return nil }
        return (n * sumXY - sumX * sumY) / denominator * 7
    }
}
