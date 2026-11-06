import Foundation
import SwiftData

enum HistorySync {
    /// Записва точките (по една на показател, ден и източник); новите стойности заменят старите.
    static func store(_ points: [MetricPoint], in context: ModelContext) {
        guard !points.isEmpty else { return }
        let existing = (try? context.fetch(FetchDescriptor<DailyMetric>())) ?? []
        var index: [String: DailyMetric] = [:]
        for metric in existing {
            index[key(metric.kindRaw, metric.sourceRaw, metric.day)] = metric
        }
        for point in points {
            let k = key(point.kind.rawValue, point.source.rawValue, point.day)
            if let metric = index[k] {
                metric.value = point.value
            } else {
                let metric = DailyMetric(day: point.day, kind: point.kind, value: point.value, source: point.source)
                context.insert(metric)
                index[k] = metric
            }
        }
        try? context.save()
    }

    private static func key(_ kind: String, _ source: String, _ day: Date) -> String {
        "\(kind)|\(source)|\(Int(day.timeIntervalSince1970))"
    }

    /// Начало на деня по местно време.
    static func dayStart(_ date: Date) -> Date { Calendar.current.startOfDay(for: date) }

    /// Внос на теглото от Apple Health: пропуска вече внесените и съвпадащите с ръчен запис в същия ден.
    @discardableResult
    static func importWeights(_ samples: [HealthService.WeightSample], in context: ModelContext) -> Int {
        guard !samples.isEmpty else { return 0 }
        let existing = (try? context.fetch(FetchDescriptor<WeightEntry>())) ?? []
        let knownIds = Set(existing.map(\.healthId).filter { !$0.isEmpty })
        var manualByDay: [Date: [Double]] = [:]
        for entry in existing where entry.healthId.isEmpty {
            manualByDay[dayStart(entry.date), default: []].append(entry.kg)
        }
        var added = 0
        for sample in samples where sample.kg > 20 && !knownIds.contains(sample.id) {
            if let kgs = manualByDay[dayStart(sample.date)], kgs.contains(where: { abs($0 - sample.kg) < 0.05 }) { continue }
            context.insert(WeightEntry(date: sample.date, kg: sample.kg, healthId: sample.id))
            added += 1
        }
        if added > 0 { try? context.save() }
        return added
    }
}

/// Имена на тренировките по дни от WHOOP и Apple Health (напр. "Running", 32 мин), за картата "Тренировки по дни".
/// Пазят се в UserDefaults: малко данни, без нов SwiftData модел.
enum WorkoutNames {
    struct Item: Hashable {
        let name: String
        let minutes: Int
    }

    private static func storageKey(_ source: MetricSource) -> String { "workoutNames.\(source.rawValue)" }

    private static func dayKey(_ date: Date) -> String {
        String(Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970))
    }

    /// Новите дни заменят старите; по-старите дни (извън периода на заявката) остават.
    static func save(_ workouts: [(start: Date, name: String, minutes: Double)], source: MetricSource) {
        guard !workouts.isEmpty else { return }
        let key = storageKey(source)
        var all = (UserDefaults.standard.dictionary(forKey: key) as? [String: [String]]) ?? [:]
        let grouped = Dictionary(grouping: workouts) { dayKey($0.start) }
        for (day, items) in grouped {
            all[day] = items.sorted { $0.start < $1.start }.map { "\($0.name)|\(Int($0.minutes.rounded()))" }
        }
        UserDefaults.standard.set(all, forKey: key)
    }

    /// WHOOP има предимство; Health се ползва за дни без WHOOP тренировки.
    static func items(on date: Date) -> [Item] {
        let day = dayKey(date)
        for source in [MetricSource.whoop, .health] {
            let all = (UserDefaults.standard.dictionary(forKey: storageKey(source)) as? [String: [String]]) ?? [:]
            if let list = all[day], !list.isEmpty {
                return list.map { entry in
                    let parts = entry.split(separator: "|", maxSplits: 1).map(String.init)
                    return Item(name: parts.first ?? "", minutes: Int(parts.count > 1 ? parts[1] : "") ?? 0)
                }
            }
        }
        return []
    }
}
