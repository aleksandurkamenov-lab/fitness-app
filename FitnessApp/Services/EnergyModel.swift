import Foundation

/// Дневен разход по три начина: формула, данни от устройствата и „реален“ от промяната в теглото срещу приема.
enum EnergyModel {
    struct Params {
        var sex: Sex
        var heightCm: Double
        var age: Int
        var activityFactor: Double
        var bodyFat: Double = 0
    }

    struct WeekPoint: Identifiable {
        let weekStart: Date
        var kg: Double?
        var intake: Double?
        /// Базов обмен (BMR): разход в пълен покой за 24 ч.
        var bmr: Double?
        var formula: Double?
        var device: Double?
        var real: Double?
        var id: Date { weekStart }
    }

    /// Ден с поне толкова записани ккал се брои за записан (пропуска дните без записана храна).
    static let minLoggedKcal = 800.0
    /// 1 кг телесна маса ≈ 7700 ккал.
    static let kcalPerKg = 7700.0
    /// Термичен ефект на храната: ~10% над базовия обмен и активните калории.
    static let thermicFactor = 1.1

    /// Наклон на теглото в кг на ден (линейна регресия), ако има поне 4 измервания за поне 7 дни.
    static func slopePerDay(_ points: [(date: Date, kg: Double)]) -> Double? {
        let sorted = points.sorted { $0.date < $1.date }
        guard sorted.count >= 4, let first = sorted.first, let last = sorted.last,
              last.date.timeIntervalSince(first.date) >= 7 * 86_400 else { return nil }
        let xs = sorted.map { $0.date.timeIntervalSince(first.date) / 86_400 }
        let ys = sorted.map(\.kg)
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        var numerator = 0.0
        var denominator = 0.0
        for index in xs.indices {
            numerator += (xs[index] - meanX) * (ys[index] - meanY)
            denominator += (xs[index] - meanX) * (xs[index] - meanX)
        }
        guard denominator > 0 else { return nil }
        return numerator / denominator
    }

    /// Реален разход = среден прием − промяна на теглото × 7700 / дни. Нужни са поне 10 записани дни и тегло.
    static func realExpenditure(intakeByDay: [Date: Double], weights: [(date: Date, kg: Double)],
                                endingAt end: Date, windowDays: Int = 21) -> Double? {
        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: end)
        guard let start = calendar.date(byAdding: .day, value: -(windowDays - 1), to: endDay) else { return nil }
        let logged = intakeByDay.filter { $0.key >= start && $0.key <= endDay && $0.value >= minLoggedKcal }
        guard logged.count >= 10 else { return nil }
        let inWindow = weights.filter { $0.date >= start && $0.date < endDay.addingTimeInterval(86_400) }
        guard let slope = slopePerDay(inWindow) else { return nil }
        let meanIntake = logged.values.reduce(0, +) / Double(logged.count)
        return meanIntake - slope * kcalPerKg
    }

    static func weeks(params: Params, weights: [(date: Date, kg: Double)], intakeByDay: [Date: Double],
                      activeByDay: [Date: Double], count: Int = 8, now: Date = .now) -> [WeekPoint] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        let sortedWeights = weights.sorted { $0.date < $1.date }
        var result: [WeekPoint] = []
        for offset in stride(from: count - 1, through: 0, by: -1) {
            guard let start = calendar.date(byAdding: .day, value: -7 * offset, to: currentWeek),
                  let end = calendar.date(byAdding: .day, value: 7, to: start) else { continue }
            let lastDay = min(end, calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? end)
            var point = WeekPoint(weekStart: start)

            let inWeek = sortedWeights.filter { $0.date >= start && $0.date < end }
            point.kg = inWeek.isEmpty ? nil : inWeek.map(\.kg).reduce(0, +) / Double(inWeek.count)
            let referenceKg = point.kg ?? sortedWeights.last(where: { $0.date < end })?.kg

            let loggedIntake = intakeByDay.filter { $0.key >= start && $0.key < lastDay && $0.value >= minLoggedKcal }
            if loggedIntake.count >= 3 {
                point.intake = loggedIntake.values.reduce(0, +) / Double(loggedIntake.count)
            }

            if let kg = referenceKg {
                let bmr = BodyMath.bmr(sex: params.sex, kg: kg, cm: params.heightCm, age: params.age, bodyFat: params.bodyFat)
                point.bmr = bmr
                point.formula = BodyMath.tdee(bmr: bmr, activity: params.activityFactor)
                let active = activeByDay.filter { $0.key >= start && $0.key < lastDay && $0.value > 0 }
                if active.count >= 3 {
                    let meanActive = active.values.reduce(0, +) / Double(active.count)
                    point.device = (bmr + meanActive) * thermicFactor
                }
            }
            point.real = realExpenditure(intakeByDay: intakeByDay, weights: sortedWeights, endingAt: lastDay.addingTimeInterval(-1))
            result.append(point)
        }
        return result
    }
}
