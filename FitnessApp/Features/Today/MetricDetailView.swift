import SwiftUI
import SwiftData
import Charts

/// Тенденции в стил WHOOP: Седмица / Месец / 6 месеца, средно, промяна спрямо предишния период и навигация по периоди.
struct MetricDetailView: View {
    let target: TrendTarget
    @Query(sort: \DailyMetric.day) private var metrics: [DailyMetric]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @State private var period: Period = .week
    @State private var offset = 0

    enum Period: String, CaseIterable, Identifiable {
        case week = "С", month = "М", sixMonths = "6М"
        var id: String { rawValue }
        var days: Int { self == .week ? 7 : (self == .month ? 30 : 182) }
        var prior: String { self == .week ? "предходната седмица" : (self == .month ? "предходния месец" : "предходните 6 месеца") }
    }

    private var kind: MetricKind? {
        if case .metric(let kind) = target { return kind }
        return nil
    }

    private var unit: String { kind?.unit ?? "кг" }
    private var digits: Int { kind?.digits ?? 1 }
    private var isBar: Bool { kind == .steps || kind == .activeKcal }

    private var today: Date { Calendar.current.startOfDay(for: .now) }
    /// Край (изключен) и начало на избрания период; offset 0 = до днес включително.
    private var end: Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return calendar.date(byAdding: .day, value: -offset * period.days, to: tomorrow) ?? tomorrow
    }
    private var from: Date { Calendar.current.date(byAdding: .day, value: -period.days, to: end) ?? .distantPast }
    private var previousFrom: Date { Calendar.current.date(byAdding: .day, value: -period.days, to: from) ?? .distantPast }

    /// Дневни стойности (за теглото: по едно на ден, средно).
    private func values(from start: Date, to end: Date) -> [DayValue] {
        switch target {
        case .metric(let kind):
            return MetricSeries.series(kind, in: metrics, from: start, to: end)
        case .weight:
            let calendar = Calendar.current
            let inRange = weights.filter { $0.date >= start && $0.date < end }
            let byDay: [Date: [WeightEntry]] = Dictionary(grouping: inRange) { calendar.startOfDay(for: $0.date) }
            var result: [DayValue] = []
            for (day, entries) in byDay {
                let total = entries.reduce(0.0) { $0 + $1.kg }
                result.append(DayValue(day: day, value: total / Double(entries.count)))
            }
            return result.sorted { $0.day < $1.day }
        }
    }

    private var current: [DayValue] { values(from: from, to: end) }
    private var previous: [DayValue] { values(from: previousFrom, to: from) }

    private func average(_ data: [DayValue]) -> Double? {
        data.isEmpty ? nil : data.map(\.value).reduce(0, +) / Double(data.count)
    }

    private func text(_ value: Double?) -> String {
        guard let value else { return "–" }
        return value.formatted(.number.precision(.fractionLength(digits)))
    }

    private struct MonthAverage: Identifiable {
        let start: Date
        let end: Date
        let value: Double
        let percent: Double?
        var id: Date { start }
    }

    private var monthAverages: [MonthAverage] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: current) { item in
            calendar.dateInterval(of: .month, for: item.day)?.start ?? item.day
        }
        var result: [MonthAverage] = []
        var previousValue: Double?
        for key in grouped.keys.sorted() {
            guard let items = grouped[key] else { continue }
            let days = items.map(\.day)
            let value = items.map(\.value).reduce(0, +) / Double(items.count)
            let percent = previousValue.flatMap { $0 != 0 ? (value - $0) / $0 * 100 : nil }
            result.append(MonthAverage(start: days.min() ?? key, end: days.max() ?? key, value: value, percent: percent))
            previousValue = value
        }
        return result
    }

    private func percentText(_ percent: Double) -> String {
        let rounded = percent.formatted(.number.precision(.fractionLength(0)))
        return (percent > 0.5 ? "+" : "") + rounded + "%"
    }

    private var rangeLabel: String {
        let last = Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end
        let format = Date.FormatStyle().day().month(.abbreviated)
        return "\(from.formatted(format)) – \(last.formatted(format)) \(last.formatted(.dateTime.year()))"
    }

    private func sentence(avg: Double, previousAvg: Double?) -> String {
        guard let previousAvg, previousAvg != 0 else {
            return "Средно „\(target.title)“ за периода: \(text(avg)) \(unit). Няма данни за \(period.prior)."
        }
        let percent = (avg - previousAvg) / previousAvg * 100
        let relation = abs(percent) < 1 ? "в съответствие с" : (percent > 0 ? "над" : "под")
        return "Средно „\(target.title)“ за периода (\(text(avg)) \(unit)) беше \(relation) средното за \(period.prior): \(text(previousAvg)) \(unit)."
    }

    var body: some View {
        let data = current
        let avg = average(data)
        let previousAvg = average(previous)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("СРЕДНО").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(text(avg)).font(.system(size: 44, weight: .bold))
                            Text(unit).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let avg, let previousAvg, previousAvg != 0 {
                            let percent = (avg - previousAvg) / previousAvg * 100
                            Label("\(percentText(percent)) спрямо \(period.prior)",
                                  systemImage: abs(percent) < 1 ? "circle.fill" : (percent > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill"))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 10) {
                        Picker("Период", selection: $period) {
                            ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                        .onChange(of: period) { offset = 0 }
                        HStack {
                            Button { offset += 1 } label: { Image(systemName: "chevron.left") }
                            Text(rangeLabel).font(.caption.weight(.semibold)).multilineTextAlignment(.center)
                            Button { offset = max(0, offset - 1) } label: { Image(systemName: "chevron.right") }
                                .disabled(offset == 0)
                        }
                    }
                }

                if let avg, data.count >= 2 {
                    Text(sentence(avg: avg, previousAvg: previousAvg)).font(.body)
                    chart(data: data, avg: avg)
                    HStack {
                        if let last = data.last {
                            Text("Последно: \(last.day.formatted(date: .abbreviated, time: .omitted))")
                        }
                        Spacer()
                        Text(target == .weight ? "Health / ръчно въведено" : "Health / WHOOP")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        stat("Най-ниско", data.map(\.value).min())
                        stat("Най-високо", data.map(\.value).max())
                    }
                } else {
                    Text("Още няма достатъчно данни за този период. Отвори таб Днес и плъзни надолу, за да се заредят.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(target.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stat(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(text(value)) \(unit)").font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var axisUnit: Calendar.Component { period == .sixMonths ? .month : .day }
    private var axisCount: Int { period == .month ? 7 : 1 }
    private var axisFormat: Date.FormatStyle {
        switch period {
        case .week: .dateTime.weekday(.abbreviated).day()
        case .month: .dateTime.month(.abbreviated).day()
        case .sixMonths: .dateTime.month(.abbreviated)
        }
    }

    private func chart(data: [DayValue], avg: Double) -> some View {
        let sixMonths = period == .sixMonths
        let months = sixMonths ? monthAverages : []
        return Chart {
            ForEach(data) { point in
                if isBar {
                    BarMark(x: .value("Ден", point.day, unit: .day), y: .value(target.title, point.value))
                        .foregroundStyle(Color.accentColor.opacity(sixMonths ? 0.35 : 1))
                } else {
                    AreaMark(x: .value("Ден", point.day), y: .value(target.title, point.value))
                        .foregroundStyle(Color.accentColor.opacity(0.08))
                    LineMark(x: .value("Ден", point.day), y: .value(target.title, point.value))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.accentColor.opacity(sixMonths ? 0.4 : 1))
                    if period == .week {
                        PointMark(x: .value("Ден", point.day), y: .value(target.title, point.value))
                            .symbolSize(40)
                            .annotation(position: .top) {
                                Text(text(point.value)).font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor)
                            }
                    }
                }
            }
            if period == .month {
                RuleMark(y: .value("Средно", avg))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .leading) {
                        Text("СР.").font(.caption2.weight(.bold)).padding(.horizontal, 4)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                    }
                if let last = data.last {
                    PointMark(x: .value("Ден", last.day), y: .value(target.title, last.value))
                        .symbolSize(40)
                        .annotation(position: .top) {
                            Text(text(last.value)).font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor)
                        }
                }
            }
            if sixMonths {
                ForEach(months) { month in
                    RuleMark(xStart: .value("От", month.start), xEnd: .value("До", month.end), y: .value("Средно", month.value))
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        .foregroundStyle(.primary)
                        .annotation(position: .top) {
                            VStack(spacing: 0) {
                                Text(text(month.value)).font(.caption2.weight(.bold))
                                if let percent = month.percent {
                                    Text(percentText(percent)).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                }
            }
        }
        .chartXScale(domain: from...end)
        .chartYScale(domain: isBar ? .automatic : .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .stride(by: axisUnit, count: axisCount)) { _ in
                AxisValueLabel(format: axisFormat)
            }
        }
        .chartScrub(data.map { ScrubPoint(date: $0.day, value: $0.value, text: "\(scrubDate($0.day)): \(text($0.value)) \(unit)") })
        .padding(.top, 28)
        .frame(height: 300)
    }
}
