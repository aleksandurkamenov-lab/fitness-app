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
