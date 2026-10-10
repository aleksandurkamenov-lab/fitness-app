import SwiftUI
import SwiftData
import Charts

/// Подробности за един показател: 7 / 30 / 90 дни, график, статистика и средно по седмици.
struct MetricDetailView: View {
    let target: TrendTarget
    @Query(sort: \DailyMetric.day) private var metrics: [DailyMetric]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @State private var rangeDays = 30

    private var kind: MetricKind? {
        if case .metric(let kind) = target { return kind }
        return nil
    }

    private var unit: String { kind?.unit ?? "кг" }
    private var digits: Int { kind?.digits ?? 1 }
    private var isBar: Bool { kind == .steps || kind == .activeKcal }

    private var today: Date { Calendar.current.startOfDay(for: .now) }
    private var from: Date { Calendar.current.date(byAdding: .day, value: -rangeDays, to: today) ?? .distantPast }
    private var previousFrom: Date { Calendar.current.date(byAdding: .day, value: -rangeDays, to: from) ?? .distantPast }

    /// Дневни стойности (за теглото: по едно на ден, средно).
    private func values(from start: Date, to end: Date) -> [DayValue] {
        switch target {
        case .metric(let kind):
            return MetricSeries.series(kind, in: metrics, from: start, to: end)
        case .weight:
            let calendar = Calendar.current
            let inRange = weights.filter { $0.date >= start && $0.date < end }
            return Dictionary(grouping: inRange) { calendar.startOfDay(for: $0.date) }
                .map { DayValue(day: $0.key, value: $0.value.map(\.kg).reduce(0, +) / Double($0.value.count)) }
                .sorted { $0.day < $1.day }
        }
    }

    private var current: [DayValue] { values(from: from, to: .distantFuture) }
    private var previous: [DayValue] { values(from: previousFrom, to: from) }

    private func average(_ data: [DayValue]) -> Double? {
        data.isEmpty ? nil : data.map(\.value).reduce(0, +) / Double(data.count)
    }

    private func text(_ value: Double?) -> String {
        guard let value else { return "–" }
        return value.formatted(.number.precision(.fractionLength(digits)))
    }

    private struct Week: Identifiable {
        let start: Date
        let average: Double
        var id: Date { start }
    }

    private var weeks: [Week] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: current) { item in
            calendar.dateInterval(of: .weekOfYear, for: item.day)?.start ?? item.day
        }
        return grouped.map { Week(start: $0.key, average: $0.value.map(\.value).reduce(0, +) / Double($0.value.count)) }
            .sorted { $0.start > $1.start }
    }

    var body: some View {
        let data = current
        let avg = average(data)
        let previousAvg = average(previous)
        List {
            Section {
                Picker("Период", selection: $rangeDays) {
                    Text("7 дни").tag(7)
                    Text("30 дни").tag(30)
                    Text("90 дни").tag(90)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if data.count >= 2 {
                Section {
                    Chart(data) { point in
                        if isBar {
                            BarMark(x: .value("Ден", point.day, unit: .day), y: .value(target.title, point.value))
                        } else {
                            LineMark(x: .value("Ден", point.day), y: .value(target.title, point.value))
                                .interpolationMethod(.catmullRom)
                            PointMark(x: .value("Ден", point.day), y: .value(target.title, point.value))
                                .symbolSize(20)
                        }
                        if let avg {
                            RuleMark(y: .value("Средно", avg))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartYScale(domain: isBar ? .automatic : .automatic(includesZero: false))
                    .frame(height: 220)
                }
            } else {
                Section {
                    Text("Още няма достатъчно данни за този период. Отвори таб Днес и плъзни надолу, за да се заредят.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Статистика (\(rangeDays) дни)") {
                LabeledContent("Средно", value: "\(text(avg)) \(unit)")
                LabeledContent("Най-ниско", value: "\(text(data.map(\.value).min())) \(unit)")
                LabeledContent("Най-високо", value: "\(text(data.map(\.value).max())) \(unit)")
                if let avg, let previousAvg, previousAvg != 0 {
                    let change = avg - previousAvg
                    let percent = change / previousAvg * 100
                    LabeledContent("Спрямо предишните \(rangeDays) дни",
                                   value: "\(change > 0 ? "+" : "")\(text(change)) \(unit) (\(percent > 0 ? "+" : "")\(percent.formatted(.number.precision(.fractionLength(0...1))))%)")
                }
                if let last = data.last {
                    LabeledContent("Последно (\(last.day.formatted(date: .abbreviated, time: .omitted)))",
                                   value: "\(text(last.value)) \(unit)")
                }
            }

            if !weeks.isEmpty {
                Section("Средно по седмици") {
                    ForEach(weeks) { week in
                        LabeledContent("от \(week.start.formatted(date: .abbreviated, time: .omitted))",
                                       value: "\(text(week.average)) \(unit)")
                    }
                }
            }
        }
        .navigationTitle(target.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
