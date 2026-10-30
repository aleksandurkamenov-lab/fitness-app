import Foundation
import HealthKit
import Observation

/// Данните за деня от Apple Health.
struct HealthSnapshot {
    var asleepHours: Double?
    var inBedHours: Double?
    var sleepStart: Date?
    var sleepEnd: Date?
    var sleepSource: String?
    var hrv: Double?
    var rhr: Double?
    var respiratory: Double?
    var oxygen: Double?
    var skinTempDelta: Double?
    var steps: Double?
    var activeKcal: Double?
    var avgSteps: Double?
    var avgActiveKcal: Double?
    /// Обща енергия на деня от WHOOP (с базовия обмен), ако е свързан.
    var whoopTotalKcal: Double?
    var vo2Max: Double?
    var heartRates: [(date: Date, bpm: Double)] = []
    var workouts: [WorkoutInfo] = []
    var hrvBaseline: RecoveryMath.Baseline?
    var rhrBaseline: RecoveryMath.Baseline?
    var respiratoryBaseline: RecoveryMath.Baseline?
    var oxygenBaseline: RecoveryMath.Baseline?
}

struct WorkoutInfo: Identifiable {
    let id = UUID()
    let name: String
    let start: Date
    let minutes: Double
    let kcal: Double?
}

/// Изядено за ден според Apple Health (например записано от MyFitnessPal).
struct NutritionDay {
    var kcal = 0.0
    var protein = 0.0
    var carbs = 0.0
    var fat = 0.0
}

@Observable
final class HealthService {
    private let store = HKHealthStore()
    var snapshot: HealthSnapshot?
    var isLoading = false
    var errorText: String?

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Дали вече сме поискали достъп (Apple не показва дали отговорът е бил да).
    var wasRequested: Bool {
        get { UserDefaults.standard.bool(forKey: "healthRequested") }
        set { UserDefaults.standard.set(newValue, forKey: "healthRequested") }
    }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.respiratoryRate),
            HKQuantityType(.oxygenSaturation),
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
            HKQuantityType(.vo2Max),
            HKQuantityType(.appleSleepingWristTemperature),
            HKQuantityType(.bodyMass),
            HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietaryProtein),
            HKQuantityType(.dietaryCarbohydrates),
            HKQuantityType(.dietaryFatTotal),
        ]
        types.insert(HKObjectType.workoutType())
        return types
    }

    func requestAccess() async {
        guard isAvailable else {
            errorText = "Apple Health не е достъпно на това устройство."
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            wasRequested = true
            await load(age: 30)
        } catch {
            errorText = error.localizedDescription
        }
    }

    func load(age: Int) async {
        guard isAvailable, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        errorText = nil

        // Ако сме добавили нови типове данни, Apple ще покаже само липсващите разрешения.
        if let status = try? await store.statusForAuthorizationRequest(toShare: [], read: readTypes),
           status == .shouldRequest {
            try? await store.requestAuthorization(toShare: [], read: readTypes)
        }

        let calendar = Calendar.current
        let now = Date.now
        let startOfDay = calendar.startOfDay(for: now)
        // "Последната нощ": от вчера 18:00 до днес 15:00.
        let nightStart = calendar.date(byAdding: .hour, value: -6, to: startOfDay) ?? startOfDay
        let nightEnd = calendar.date(byAdding: .hour, value: 15, to: startOfDay) ?? now
        let monthAgo = calendar.date(byAdding: .day, value: -30, to: startOfDay) ?? startOfDay

        var result = HealthSnapshot()

        // Независимите заявки започват заедно; прозорецът за средните стойности
        // се определя след като пристигне обобщението за съня.
        async let sleepTask = sleepSummary(from: nightStart, to: min(nightEnd, now))
        async let hrvTask = quantitySamples(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: monthAgo, to: now)
        async let rhrTask = quantitySamples(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), from: monthAgo, to: now)
        async let respTask = quantitySamples(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()), from: monthAgo, to: now)
        async let oxygenTask = quantitySamples(.oxygenSaturation, unit: .percent(), from: monthAgo, to: now)
        async let skinTask = quantitySamples(.appleSleepingWristTemperature, unit: .degreeCelsius(), from: monthAgo, to: now)
        async let vo2Task = quantitySamples(.vo2Max, unit: HKUnit(from: "ml/(kg*min)"), from: monthAgo, to: now)

        if let sleep = try? await sleepTask {
            result.asleepHours = sleep.asleep
            result.inBedHours = sleep.inBed
            result.sleepStart = sleep.start
            result.sleepEnd = sleep.end
            result.sleepSource = sleep.source
        }

        // Показатели за последната нощ и 30-дневни лични норми
        let nightWindow = result.sleepStart.map { ($0, result.sleepEnd ?? now) } ?? (nightStart, min(nightEnd, now))

        let hrv = await hrvTask
        result.hrv = average(hrv, in: nightWindow)
        result.hrvBaseline = baseline(hrv, before: startOfDay, calendar: calendar)

        let rhr = await rhrTask
        result.rhr = rhr.last?.value
        result.rhrBaseline = baseline(rhr, before: startOfDay, calendar: calendar)

        let resp = await respTask
        result.respiratory = average(resp, in: nightWindow)
        result.respiratoryBaseline = baseline(resp, before: startOfDay, calendar: calendar)

        let oxygenFractions = await oxygenTask
        let oxygen = oxygenFractions.map { Sample(date: $0.date, value: $0.value * 100) }
        result.oxygen = average(oxygen, in: nightWindow)
        result.oxygenBaseline = baseline(oxygen, before: startOfDay, calendar: calendar)

        let skin = await skinTask
        if let latest = skin.last?.value {
            let past = skin.filter { $0.date < startOfDay }.map(\.value)
            if !past.isEmpty { result.skinTempDelta = latest - past.reduce(0, +) / Double(past.count) }
        }

        let vo2 = await vo2Task
        result.vo2Max = vo2.last?.value

        // Ден: крачки, калории, пулс, тренировки
        async let stepsTask = cumulative(.stepCount, unit: .count(), from: startOfDay, to: now)
        async let activeKcalTask = cumulative(.activeEnergyBurned, unit: .kilocalorie(), from: startOfDay, to: now)
        async let avgStepsTask = dailyAverage(.stepCount, unit: .count(), days: 7, calendar: calendar)
        async let avgActiveKcalTask = dailyAverage(.activeEnergyBurned, unit: .kilocalorie(), days: 7, calendar: calendar)
        async let heartTask = quantitySamples(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()), from: startOfDay, to: now)
        async let workoutsTask = todaysWorkouts(from: startOfDay, to: now)

        result.steps = await stepsTask
        result.activeKcal = await activeKcalTask
        result.avgSteps = await avgStepsTask
        result.avgActiveKcal = await avgActiveKcalTask
        let heart = await heartTask
        result.heartRates = heart.map { ($0.date, $0.value) }
        result.workouts = await workoutsTask

        snapshot = result
    }

    // MARK: Заявки

    private struct SleepSummary {
        var asleep: Double
        var inBed: Double?
        var start: Date
        var end: Date
        var source: String
    }

    private struct Sample {
        let date: Date
        let value: Double
    }

    private func sleepSummary(from: Date, to: Date) async throws -> SleepSummary? {
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await descriptor.result(for: store)
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        // Ако има няколко източника (напр. WHOOP и телефон), взимаме този с най-много сън.
        let bySource = Dictionary(grouping: samples) { $0.sourceRevision.source.name }
        var best: (name: String, asleep: Double, inBed: Double, start: Date, end: Date)?
        for (name, items) in bySource {
            let asleepItems = items.filter { asleepValues.contains($0.value) }
            guard !asleepItems.isEmpty else { continue }
            let asleep = asleepItems.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 3600
            let inBed = items.filter { $0.value == HKCategoryValueSleepAnalysis.inBed.rawValue }
                .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 3600
            let start = asleepItems.map(\.startDate).min() ?? from
            let end = asleepItems.map(\.endDate).max() ?? to
            if best == nil || asleep > best!.asleep {
                best = (name, asleep, inBed, start, end)
            }
        }
        guard let best else { return nil }
        return SleepSummary(asleep: best.asleep, inBed: best.inBed > 0 ? best.inBed : nil,
                            start: best.start, end: best.end, source: best.name)
    }

    private func quantitySamples(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from: Date, to: Date) async -> [Sample] {
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = (try? await descriptor.result(for: store)) ?? []
        return samples.map { Sample(date: $0.startDate, value: $0.quantity.doubleValue(for: unit)) }
    }

    private func cumulative(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from: Date, to: Date) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(identifier), predicate: predicate),
            options: .cumulativeSum
        )
        let stats = try? await descriptor.result(for: store)
        return stats?.sumQuantity()?.doubleValue(for: unit)
    }

    /// Средно на ден за последните дни (без днес).
    private func dailyAverage(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, days: Int, calendar: Calendar) async -> Double? {
        let today = calendar.startOfDay(for: .now)
        guard days > 0,
              let from = calendar.date(byAdding: .day, value: -days, to: today) else { return nil }
        let daily = await dailyTotals(identifier, unit: unit, from: from, to: today)
        let totals = daily.values.filter { $0 > 0 }
        return totals.isEmpty ? nil : totals.reduce(0, +) / Double(totals.count)
    }

    private func todaysWorkouts(from: Date, to: Date) async -> [WorkoutInfo] {
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let workouts = (try? await descriptor.result(for: store)) ?? []
        return workouts.map { workout in
            let kcal = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?.doubleValue(for: .kilocalorie())
            return WorkoutInfo(name: Self.title(for: workout.workoutActivityType),
                               start: workout.startDate,
                               minutes: workout.duration / 60,
                               kcal: kcal)
        }
    }

    private static func title(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .traditionalStrengthTraining, .functionalStrengthTraining: "Силова тренировка"
        case .running: "Бягане"
        case .walking: "Ходене"
        case .cycling: "Колоездене"
        case .swimming: "Плуване"
        case .highIntensityIntervalTraining: "HIIT"
        case .yoga: "Йога"
        default: "Тренировка"
        }
    }

    // MARK: Помощни

    private func average(_ samples: [Sample], in window: (Date, Date)) -> Double? {
        let values = samples.filter { $0.date >= window.0 && $0.date <= window.1 }.map(\.value)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// Лична норма: средно от дневните средни за последните дни преди днес.
    private func baseline(_ samples: [Sample], before day: Date, calendar: Calendar) -> RecoveryMath.Baseline? {
        let past = samples.filter { $0.date < day }
        let grouped = Dictionary(grouping: past) { calendar.startOfDay(for: $0.date) }
        let dailyMeans = grouped.values.map { $0.map(\.value).reduce(0, +) / Double($0.count) }
        return RecoveryMath.Baseline(values: dailyMeans)
    }

    // MARK: История

    struct WeightSample {
        let id: String
        let date: Date
        let kg: Double
    }

    /// Всички измервания на теглото от Apple Health (за внос).
    func weightHistory() async -> [WeightSample] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: .distantPast, end: .now, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = (try? await descriptor.result(for: store)) ?? []
        return samples.map {
            WeightSample(id: $0.uuid.uuidString, date: $0.startDate,
                         kg: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)))
        }
    }

    /// Дневна история на показателите за последните дни.
    func history(days: Int) async -> [MetricPoint] {
        guard isAvailable else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let from = calendar.date(byAdding: .day, value: -days, to: today) else { return [] }
        var points: [MetricPoint] = []

        func dailyMeans(_ samples: [Sample], scale: Double = 1) -> [Date: Double] {
            Dictionary(grouping: samples) { calendar.startOfDay(for: $0.date) }
                .mapValues { $0.map(\.value).reduce(0, +) / Double($0.count) * scale }
        }
        func add(_ kind: MetricKind, _ values: [Date: Double]) {
            for (day, value) in values {
                points.append(MetricPoint(kind: kind, day: day, value: value, source: .health))
            }
        }

        add(.hrv, dailyMeans(await quantitySamples(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: from, to: .now)))
        add(.rhr, dailyMeans(await quantitySamples(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), from: from, to: .now)))
        add(.respiratory, dailyMeans(await quantitySamples(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()), from: from, to: .now)))
        add(.spo2, dailyMeans(await quantitySamples(.oxygenSaturation, unit: .percent(), from: from, to: .now), scale: 100))
        add(.skinTemp, dailyMeans(await quantitySamples(.appleSleepingWristTemperature, unit: .degreeCelsius(), from: from, to: .now)))

        add(.steps, await dailyTotals(.stepCount, unit: .count(), from: from))
        add(.activeKcal, await dailyTotals(.activeEnergyBurned, unit: .kilocalorie(), from: from))
        add(.sleepHours, await sleepHoursByDay(from: from))

        // Минути тренировки и кардио по дни (до 12 месеца назад, за heatmap-а).
        let workoutFrom = calendar.date(byAdding: .day, value: -365, to: today) ?? from
        let predicate = HKQuery.predicateForSamples(withStart: workoutFrom, end: .now, options: [])
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [SortDescriptor(\.startDate)])
        let workouts = (try? await descriptor.result(for: store)) ?? []
        var workoutMinutes: [Date: Double] = [:]
        var strengthSessions: [Date: Double] = [:]
        var cardioSessions: [Date: Double] = [:]
        for workout in workouts {
            let day = calendar.startOfDay(for: workout.startDate)
            let minutes = workout.duration / 60
            workoutMinutes[day, default: 0] += minutes
            let isStrength: Bool
            switch workout.workoutActivityType {
            case .traditionalStrengthTraining, .functionalStrengthTraining: isStrength = true
            case .running, .walking, .cycling, .swimming, .highIntensityIntervalTraining, .rowing, .elliptical,
                 .stairClimbing, .hiking, .jumpRope, .cardioDance, .kickboxing, .boxing, .mixedCardio:
                isStrength = false
            default: isStrength = minutes >= 35
            }
            if isStrength { strengthSessions[day, default: 0] += 1 } else { cardioSessions[day, default: 0] += 1 }
        }
        add(.workoutMinutes, workoutMinutes)
        add(.strengthSessions, strengthSessions)
        add(.cardioSessions, cardioSessions)
        return points
    }

    /// Калории и макроси по дни от Health за последните `days` дни.
    func nutrition(days: Int) async -> [Date: NutritionDay] {
        guard isAvailable else { return [:] }
        if let status = try? await store.statusForAuthorizationRequest(toShare: [], read: readTypes),
           status == .shouldRequest {
            try? await store.requestAuthorization(toShare: [], read: readTypes)
        }
        let calendar = Calendar.current
        let from = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: .now)) ?? .now
        async let kcalTask = dailyTotals(.dietaryEnergyConsumed, unit: .kilocalorie(), from: from)
        async let proteinTask = dailyTotals(.dietaryProtein, unit: .gram(), from: from)
        async let carbsTask = dailyTotals(.dietaryCarbohydrates, unit: .gram(), from: from)
        async let fatTask = dailyTotals(.dietaryFatTotal, unit: .gram(), from: from)
        let (kcal, protein, carbs, fat) = await (kcalTask, proteinTask, carbsTask, fatTask)
        var result: [Date: NutritionDay] = [:]
        for (day, value) in kcal { result[day, default: NutritionDay()].kcal = value }
        for (day, value) in protein { result[day, default: NutritionDay()].protein = value }
        for (day, value) in carbs { result[day, default: NutritionDay()].carbs = value }
        for (day, value) in fat { result[day, default: NutritionDay()].fat = value }
        return result
    }

    private func dailyTotals(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from: Date,
                             to: Date = .now) async -> [Date: Double] {
        let calendar = Calendar.current
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(identifier), predicate: predicate),
            options: .cumulativeSum,
            anchorDate: calendar.startOfDay(for: from),
            intervalComponents: DateComponents(day: 1)
        )
        guard let collection = try? await descriptor.result(for: store) else { return [:] }
        var result: [Date: Double] = [:]
        collection.enumerateStatistics(from: from, to: to) { statistics, _ in
            if let value = statistics.sumQuantity()?.doubleValue(for: unit), value > 0 {
                result[calendar.startOfDay(for: statistics.startDate)] = value
            }
        }
        return result
    }

    /// Часове сън за всеки ден (по деня на събуждане), от източника с най-много сън.
    private func sleepHoursByDay(from: Date) async -> [Date: Double] {
        let calendar = Calendar.current
        let predicate = HKQuery.predicateForSamples(withStart: from, end: .now, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = (try? await descriptor.result(for: store)) ?? []
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        let asleep = samples.filter { asleepValues.contains($0.value) }
        var result: [Date: Double] = [:]
        for (day, items) in Dictionary(grouping: asleep, by: { calendar.startOfDay(for: $0.endDate) }) {
            let bySource = Dictionary(grouping: items) { $0.sourceRevision.source.name }
            let best = bySource.values.map { group in
                group.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 3600
            }.max() ?? 0
            if best > 0 { result[day] = best }
        }
        return result
    }
}
