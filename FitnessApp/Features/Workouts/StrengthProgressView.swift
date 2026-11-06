import SwiftUI
import SwiftData
import Charts

/// Силов прогрес: приблизителен 1RM по упражнения във времето и седмичен тонаж.
struct StrengthProgressView: View {
    @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
    @State private var weeks = 12
    @State private var selectedName: String?

    private struct Point: Identifiable {
        let date: Date
        let value: Double
        let name: String
        var id: String { "\(name)-\(date.timeIntervalSince1970)" }
    }

    private struct Summary: Identifiable {
        let name: String
        let points: [Point]
        var id: String { name }
        var first: Double { points.first?.value ?? 0 }
        var last: Double { points.last?.value ?? 0 }
        var change: Double { first > 0 ? (last - first) / first * 100 : 0 }
    }

    private struct WeekVolume: Identifiable {
        let week: Date
        let kg: Double
        var id: Date { week }
    }

    private var fromDate: Date {
        guard weeks > 0 else { return .distantPast }
        return Calendar.current.date(byAdding: .day, value: -7 * weeks, to: .now) ?? .distantPast
    }

    private var periodSessions: [WorkoutSession] {
        sessions.filter { $0.isFinished && $0.date >= fromDate }
    }

    /// Най-добрият 1RM за всяка тренировка, по упражнение.
    private func summaries(_ list: [WorkoutSession]) -> [Summary] {
        var byName: [String: [Point]] = [:]
        for session in list {
            var best: [String: Double] = [:]
            for set in session.sets where set.isWorkSet && set.repsValue > 0 {
                let name = set.exercise?.name ?? "Упражнение"
                best[name] = max(best[name] ?? 0, set.estimatedOneRepMax)
            }
            for (name, value) in best where value > 0 {
                byName[name, default: []].append(Point(date: session.date, value: value, name: name))
            }
        }
        return byName.map { Summary(name: $0.key, points: $0.value) }
            .sorted { ($0.points.count, $1.name) > ($1.points.count, $0.name) }
    }

    private func weeklyVolume(_ list: [WorkoutSession]) -> [WeekVolume] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        var totals: [Date: Double] = [:]
        for session in list {
            let week = calendar.dateInterval(of: .weekOfYear, for: session.date)?.start ?? session.date
            totals[week, default: 0] += WorkoutMath.totalVolume(session.sets)
        }
        guard let first = totals.keys.min(), let last = totals.keys.max() else { return [] }
        // Пълни и празните седмици с 0, за да няма "дупки" в оста.
        var result: [WeekVolume] = []
        var week = first
        while week <= last {
            result.append(WeekVolume(week: week, kg: totals[week] ?? 0))
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: week) else { break }
            week = next
        }
        return result
    }

    private func tons(_ kg: Double) -> String {
        (kg / 1000).formatted(.number.precision(.fractionLength(0...1))) + " т"
    }

    private func weekRange(_ start: Date) -> String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        let f = Date.FormatStyle().day().month(.defaultDigits)
        return "\(start.formatted(f)) – \(end.formatted(f))"
    }

    private func changeText(_ value: Double) -> String {
        (value >= 0 ? "+" : "") + value.formatted(.number.precision(.fractionLength(0...1))) + " %"
    }

    var body: some View {
        let list = periodSessions
        let all = summaries(list)
        let top = Array(all.filter { $0.points.count >= 2 }.prefix(5))
        let normalized = top.flatMap { summary in
            summary.points.map { Point(date: $0.date, value: ($0.value / summary.first - 1) * 100, name: summary.name) }
        }
        let selected = all.first { $0.name == selectedName } ?? all.first
        let volume = weeklyVolume(list)

        List {
            Section {
                Picker("Период", selection: $weeks) {
                    Text("4 седм.").tag(4)
                    Text("12 седм.").tag(12)
                    Text("26 седм.").tag(26)
                    Text("Всичко").tag(0)
                }
                .pickerStyle(.segmented)
            }

            if all.isEmpty {
                Section {
                    Text("Още няма завършени тренировки за този период.")
                        .foregroundStyle(.secondary)
                }
            }

            if !normalized.isEmpty {
                Section {
                    Chart(normalized) { point in
                        LineMark(x: .value("Дата", point.date), y: .value("%", point.value))
                            .foregroundStyle(by: .value("Упражнение", point.name))
                        PointMark(x: .value("Дата", point.date), y: .value("%", point.value))
                            .foregroundStyle(by: .value("Упражнение", point.name))
                    }
                    .chartLegend(position: .bottom, alignment: .leading)
                    .frame(height: 260)
                    .padding(.top, 8)
                } header: {
                    Text("Основни упражнения: промяна в %")
                } footer: {
                    Text("По приблизителен 1RM (Epley) спрямо първата тренировка в периода. Ориентировъчно.")
                }
            }

            if let selected {
                Section {
                    Chart(selected.points) { point in
                        LineMark(x: .value("Дата", point.date), y: .value("1RM", point.value))
                        PointMark(x: .value("Дата", point.date), y: .value("1RM", point.value))
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartScrub(selected.points.map {
                        ScrubPoint(date: $0.date, value: $0.value,
                                   text: trf("%@: ~%@ кг", "\(scrubDate($0.date))", "\($0.value.formatted(.number.precision(.fractionLength(0...1))))"))
                    })
                    .padding(.top, 24)
                    .frame(height: 220)
                    LabeledContent("Промяна", value: changeText(selected.change))
                    LabeledContent("Сега", value: trf("~%@ кг", "\(selected.last.short)"))
                } header: {
                    Text(trf("%@: 1RM (кг)", "\(selected.name)"))
                }
            }

            if !all.isEmpty {
                Section {
                    ForEach(all) { summary in
                        Button {
                            selectedName = summary.name
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tr(summary.name))
                                        .foregroundStyle(.primary)
                                    Text(trf("%@ тренировки · ~%@ кг", "\(summary.points.count)", "\(summary.last.short)"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if summary.points.count >= 2 {
                                    Text(changeText(summary.change))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(summary.change >= 0 ? Color.green : Color.red)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Упражнения (докосни за графика)")
                }
            }

            if !volume.isEmpty {
                Section {
                    Chart(volume) { item in
                        BarMark(x: .value("Седмица", item.week, unit: .weekOfYear), y: .value("кг", item.kg))
                            .cornerRadius(4)
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let kg = value.as(Double.self) {
                                    Text((kg / 1000).formatted(.number.precision(.fractionLength(0...1))) + " т")
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .weekOfYear, count: volume.count > 8 ? 2 : 1)) { _ in
                            AxisTick()
                            AxisValueLabel(format: .dateTime.day().month(.defaultDigits), centered: true)
                        }
                    }
                    .chartScrub(volume.map {
                        ScrubPoint(date: $0.week, value: $0.kg,
                                   text: "\(weekRange($0.week)): \(tons($0.kg))")
                    })
                    .padding(.top, 24)
                    .frame(height: 220)
                    if let last = volume.last {
                        LabeledContent(trf("Седмица от %@", "\(weekRange(last.week))"), value: tons(last.kg))
                        if volume.count >= 2, volume[volume.count - 2].kg > 0 {
                            let prev = volume[volume.count - 2].kg
                            LabeledContent("Спрямо предишната", value: changeText((last.kg - prev) / prev * 100))
                        }
                    }
                } header: {
                    Text("Седмичен тонаж")
                } footer: {
                    Text("Сума от кг × повторения, без загрявки. Етикетите са начало на седмицата (понеделник); докосни и плъзни за точна стойност.")
                }
            }
        }
        .navigationTitle("Силов прогрес")
        .navigationBarTitleDisplayMode(.inline)
    }
}
