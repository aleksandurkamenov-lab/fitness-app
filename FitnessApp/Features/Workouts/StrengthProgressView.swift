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
            for set in session.sets where set.isWorkSet && set.reps > 0 {
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
        return totals.keys.sorted().map { WeekVolume(week: $0, kg: totals[$0] ?? 0) }
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
                                   text: "\(scrubDate($0.date)): ~\($0.value.formatted(.number.precision(.fractionLength(0...1)))) кг")
                    })
                    .padding(.top, 24)
                    .frame(height: 220)
                    LabeledContent("Промяна", value: changeText(selected.change))
                    LabeledContent("Сега", value: "~\(selected.last.short) кг")
                } header: {
                    Text("\(selected.name): 1RM (кг)")
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
                                    Text(summary.name)
                                        .foregroundStyle(.primary)
                                    Text("\(summary.points.count) тренировки · ~\(summary.last.short) кг")
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
                    }
                    .chartScrub(volume.map {
                        ScrubPoint(date: $0.week, value: $0.kg,
                                   text: "Седмица от \(scrubDate($0.week)): \($0.kg.short) кг")
                    })
                    .padding(.top, 24)
                    .frame(height: 200)
                } header: {
                    Text("Седмичен тонаж (кг × повт., без загрявки)")
                }
            }
        }
        .navigationTitle("Силов прогрес")
        .navigationBarTitleDisplayMode(.inline)
    }
}
