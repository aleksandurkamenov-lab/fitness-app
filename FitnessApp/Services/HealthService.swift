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

        let calendar = Calendar.current
        let now = Date.now
        let startOfDay = calendar.startOfDay(for: now)
        // "Последната нощ": от вчера 18:00 до днес 15:00.
        let nightStart = calendar.date(byAdding: .hour, value: -6, to: startOfDay) ?? startOfDay
        let nightEnd = calendar.date(byAdding: .hour, value: 15, to: startOfDay) ?? now
        let monthAgo = calendar.date(byAdding: .day, value: -30, to: startOfDay) ?? startOfDay

        var result = HealthSnapshot()

        // Сън
        if let sleep = try? await sleepSummary(from: nightStart, to: min(nightEnd, now)) {
            result.asleepHours = sleep.asleep
            result.inBedHours = sleep.inBed
            result.sleepStart = sleep.start
            result.sleepEnd = sleep.end
            result.sleepSource = sleep.source
        }

        // Показатели за последната нощ и 30-дневни лични норми
        let nightWindow = result.sleepStart.map { ($0, result.sleepEnd ?? now) } ?? (nightStart, min(nightEnd, now))

        let hrv = await quantitySamples(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: monthAgo, to: now)
        result.hrv = average(hrv, in: nightWindow)
        result.hrvBaseline = baseline(hrv, before: startOfDay, calendar: calendar)

        let rhr = await quantitySamples(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), from: monthAgo, to: now)
        result.rhr = rhr.last?.value
        result.rhrBaseline = baseline(rhr, before: startOfDay, calendar: calendar)

        let resp = await quantitySamples(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()), from: monthAgo, to: now)
        result.respiratory = average(resp, in: nightWindow)
        result.respiratoryBaseline = baseline(resp, before: startOfDay, calendar: calendar)

        let oxygenFractions = await quantitySamples(.oxygenSaturation, unit: .percent(), from: monthAgo, to: now)
        let oxygen = oxygenFractions.map { Sample(date: $0.date, value: $0.value * 100) }
        result.oxygen = average(oxygen, in: nightWindow)
        result.oxygenBaseline = baseline(oxygen, before: startOfDay, calendar: calendar)

        let skin = await quantitySamples(.appleSleepingWristTemperature, unit: .degreeCelsius(), from: monthAgo, to: now)
        if let latest = skin.last?.value {
            let past = skin.filter { $0.date < startOfDay }.map(\.value)
            if !past.isEmpty { result.skinTempDelta = latest - past.reduce(0, +) / Double(past.count) }
        }

        let vo2 = await quantitySamples(.vo2Max, unit: HKUnit(from: "ml/(kg*min)"), from: monthAgo, to: now)
        result.vo2Max = vo2.last?.value

        // Ден: крачки, калории, пулс, тренировки
        result.steps = await cumulative(.stepCount, unit: .count(), from: startOfDay, to: now)
        result.activeKcal = await cumulative(.activeEnergyBurned, unit: .kilocalorie(), from: startOfDay, to: now)
        result.avgSteps = await dailyAverage(.stepCount, unit: .count(), days: 7, calendar: calendar)
        result.avgActiveKcal = await dailyAverage(.activeEnergyBurned, unit: .kilocalorie(), days: 7, calendar: calendar)

        let heart = await quantitySamples(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()), from: startOfDay, to: now)
        result.heartRates = heart.map { ($0.date, $0.value) }

        result.workouts = await todaysWorkouts(from: startOfDay, to: now)

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
        var totals: [Double] = []
        for offset in 1...days {
            guard let start = calendar.date(byAdding: .day, value: -offset, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: start),
                  let value = await cumulative(identifier, unit: unit, from: start, to: end), value > 0 else { continue }
            totals.append(value)
        }
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
}
