import SwiftUI
import SwiftData
import Charts

/// Карти за активността: тренировки за седмица и месец, серия от седмици, 30-дневно тегло и heatmap за 12 месеца.
struct ActivityStatsCard: View {
    @Query private var sessions: [WorkoutSession]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query private var metrics: [DailyMetric]

    private let weekCount = 53

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    private var finished: [WorkoutSession] { sessions.filter(\.isFinished) }

    private func weekStart(_ date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private var thisWeekCount: Int {
        strengthCount(from: weekStart(.now), to: .distantFuture)
    }

    private var thisMonthCount: Int {
        guard let start = calendar.dateInterval(of: .month, for: .now)?.start else { return 0 }
        return strengthCount(from: start, to: .distantFuture)
    }

    /// Поредни седмици с поне една тренировка; текущата седмица не прекъсва серията, ако още е празна.
    private var weekStreak: Int {
        let weeks = Set(finished.map { weekStart($0.date) })
        var cursor = weekStart(.now)
        if !weeks.contains(cursor) {
            cursor = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) ?? cursor
        }
        var streak = 0
        while weeks.contains(cursor) {
            streak += 1
            cursor = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) ?? .distantPast
        }
        return streak
    }

    private var weightChange30: String {
        let from = Date.now.addingTimeInterval(-30 * 86_400)
        let recent = weights.filter { $0.date >= from }
        guard let first = recent.first, let last = recent.last, recent.count >= 2 else { return "—" }
        return BodyMath.signedKg(last.kg - first.kg)
    }

    /// Минути тренировка и кардио по дни: от WHOOP/Health, а където няма такива, от записаните в приложението (45 мин).
    private var minutesByDay: [Date: Double] {
        var result: [Date: Double] = [:]
        for session in finished {
            // Тренировките от седмичната решетка нямат реално начало и край, затова се брои 45 мин.
            let minutes = session.finishedAt.map { $0.timeIntervalSince(session.date) >= 600 ? $0.timeIntervalSince(session.date) / 60 : 45 } ?? 45
            result[calendar.startOfDay(for: session.date), default: 0] += min(minutes, 180)
        }
        for point in MetricSeries.series(.workoutMinutes, in: metrics, from: .distantPast) where point.value > 0 {
            result[calendar.startOfDay(for: point.day)] = point.value
        }
        return result
    }

    /// Силови сесии по дни: най-много от приложението и от WHOOP/Health (за да не се броят два пъти).
    private var strengthByDay: [Date: Int] {
        var result: [Date: Int] = [:]
        for session in finished where !session.sets.isEmpty {
            result[calendar.startOfDay(for: session.date), default: 0] += 1
        }
        for point in MetricSeries.series(.strengthSessions, in: metrics, from: .distantPast) {
            let day = calendar.startOfDay(for: point.day)
            result[day] = max(result[day] ?? 0, Int(point.value))
        }
        return result
    }

    private var cardioByDay: [Date: Int] {
        var result: [Date: Int] = [:]
        for point in MetricSeries.series(.cardioSessions, in: metrics, from: .distantPast) {
            result[calendar.startOfDay(for: point.day)] = Int(point.value)
        }
        return result
    }

    private func count(_ byDay: [Date: Int], from start: Date, to end: Date) -> Int {
        let from = calendar.startOfDay(for: start)
        return byDay.filter { $0.key >= from && $0.key < end }.values.reduce(0, +)
    }

    private func strengthCount(from start: Date, to end: Date) -> Int { count(strengthByDay, from: start, to: end) }

    private func daysAgo(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: .now) ?? .distantPast }

    /// Последните 6 календарни седмици (пон–нед), най-новата първа.
    private var weeklyCounts: [(start: Date, end: Date, strength: Int, cardio: Int)] {
        let current = weekStart(.now)
        let strength = strengthByDay
        let cardio = cardioByDay
        return (0..<6).compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: current),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            return (start, end, count(strength, from: start, to: end), count(cardio, from: start, to: end))
        }
    }

    private var strengthSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink {
                TrainingDaysView(strength: strengthByDay, cardio: cardioByDay)
            } label: {
                HStack {
                    Text("Силови тренировки").font(.subheadline.bold())
                    Spacer()
                    Text("по дни").font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    tile("Силови, 7 дни", "\(strengthCount(from: daysAgo(6), to: .distantFuture))", "figure.strengthtraining.traditional")
                    tile("Силови, 30 дни", "\(strengthCount(from: daysAgo(29), to: .distantFuture))", "calendar")
                }
                GridRow {
                    tile("Кардио, 7 дни", "\(count(cardioByDay, from: daysAgo(6), to: .distantFuture))", "figure.run")
                    tile("Кардио, 30 дни", "\(count(cardioByDay, from: daysAgo(29), to: .distantFuture))", "calendar")
                }
            }
            Text("Цел: минимум 3–4 силови седмично (пон–нед). Силова/кардио се определя по вида в WHOOP/Health, а при неясен вид: под 35 мин е кардио.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(weeklyCounts, id: \.start) { week in
                let lastDay = calendar.date(byAdding: .day, value: -1, to: week.end) ?? week.end
                let isCurrent = week.start == weekStart(.now)
                HStack {
                    Text("\(week.start.formatted(.dateTime.day().month(.twoDigits))) – \(lastDay.formatted(.dateTime.day().month(.twoDigits)))" + (isCurrent ? " (тази)" : ""))
                        .font(.callout)
                    Spacer()
                    Text("силови \(week.strength) · кардио \(week.cardio)").font(.callout.bold())
                    Image(systemName: week.strength >= 4 ? "checkmark.circle.fill" : week.strength >= 3 ? "checkmark.circle" : isCurrent ? "clock" : "xmark.circle")
                        .foregroundStyle(week.strength >= 3 ? Color.green : isCurrent ? Color.secondary : Color.red)
                }
            }
        }
    }

    private func color(_ minutes: Double) -> Color {
        switch minutes {
        case ..<1: Color.secondary.opacity(0.15)
        case ..<30: Color.green.opacity(0.35)
        case ..<60: Color.green.opacity(0.6)
        case ..<90: Color.green.opacity(0.8)
        default: Color.green
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            tilesCard
            heatmapCard
        }
    }

    private var tilesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Активност").font(.headline)
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    tile("Тази седмица", "\(thisWeekCount)", "figure.strengthtraining.traditional")
                    tile("Този месец", "\(thisMonthCount)", "calendar")
                }
                GridRow {
                    tile("Серия седмици", "\(weekStreak)", "flame")
                    tile("Тегло 30 дни", weightChange30, "scalemass")
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Тренировки по дни").font(.headline)
            Text("12 месеца, минути тренировка и кардио от WHOOP/Health")
                .font(.caption)
                .foregroundStyle(.secondary)
            strengthSummary
            heatmap
            HStack(spacing: 4) {
                Text("по-малко").font(.caption2).foregroundStyle(.secondary)
                ForEach([0.0, 20, 45, 75, 100], id: \.self) { minutes in
                    RoundedRectangle(cornerRadius: 1.5).fill(color(minutes)).frame(width: 10, height: 10)
                }
                Text("над 90 мин").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func tile(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value).font(.title2.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var heatmap: some View {
        let minutes = minutesByDay
        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .weekOfYear, value: -(weekCount - 1), to: weekStart(today)) ?? today
        return Canvas { context, size in
            let gap: CGFloat = 2
            let cell = (size.width - gap * CGFloat(weekCount - 1)) / CGFloat(weekCount)
            for week in 0..<weekCount {
                for day in 0..<7 {
                    guard let date = calendar.date(byAdding: .day, value: week * 7 + day, to: start), date <= today else { continue }
                    let rect = CGRect(x: CGFloat(week) * (cell + gap), y: CGFloat(day) * (cell + gap), width: cell, height: cell)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color(minutes[date] ?? 0)))
                }
            }
        }
        .aspectRatio(CGFloat(weekCount) / 7.9, contentMode: .fit)
    }
}

/// Баланс на обема по мускулни групи (серии) и ориентировъчна умора/готовност.
struct MuscleBalanceView: View {
    @Query private var sessions: [WorkoutSession]
    @State private var tab = 0
    @State private var rangeDays = 7

    private var finished: [WorkoutSession] { sessions.filter(\.isFinished) }

    private var setsByMuscle: [(muscle: MuscleGroup, sets: Double)] {
        var from = Date.distantPast
        if rangeDays > 0 {
            from = Calendar.current.date(byAdding: .day, value: -rangeDays, to: .now) ?? .distantPast
        }
        let sets = finished.filter { $0.date >= from }.flatMap(\.sets)
        let totals = WorkoutMath.weeklySets(sets)
        return MuscleGroup.allCases.map { (muscle: $0, sets: totals[$0] ?? 0) }
    }

    /// Кога е тренирана за последно всяка група (основна или второстепенна) и серии за 7 дни.
    private var recovery: [(muscle: MuscleGroup, last: Date?, weekSets: Double)] {
        var last: [MuscleGroup: Date] = [:]
        for session in finished {
            for set in session.sets where set.isWorkSet {
                guard let exercise = set.exercise else { continue }
                for muscle in [exercise.primaryMuscle] + exercise.secondaryMuscles {
                    if (last[muscle] ?? .distantPast) < session.date { last[muscle] = session.date }
                }
            }
        }
        let from = Date.now.addingTimeInterval(-7 * 86_400)
        let week = WorkoutMath.weeklySets(finished.filter { $0.date >= from }.flatMap(\.sets))
        return MuscleGroup.allCases.map { (muscle: $0, last: last[$0], weekSets: week[$0] ?? 0) }
    }

    var body: some View {
        List {
            Section {
                Picker("Изглед", selection: $tab) {
                    Text("Баланс").tag(0)
                    Text("Умора").tag(1)
                }
                .pickerStyle(.segmented)
            }
            if tab == 0 { balanceSections } else { fatigueSection }
        }
        .navigationTitle("Мускули")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var balanceSections: some View {
        Section {
            Picker("Период", selection: $rangeDays) {
                Text("Седмица").tag(7)
                Text("30 дни").tag(30)
                Text("90 дни").tag(90)
                Text("Всичко").tag(0)
            }
            .pickerStyle(.segmented)
            let data = setsByMuscle
            if data.allSatisfy({ $0.sets == 0 }) {
                Text("Няма завършени тренировки за периода.").foregroundStyle(.secondary)
            } else {
                Chart(data, id: \.muscle) { item in
                    BarMark(x: .value("Серии", item.sets), y: .value("Мускул", item.muscle.title))
                        .foregroundStyle(Color.accentColor)
                        .annotation(position: .trailing) {
                            Text(item.sets.short).font(.caption2).foregroundStyle(.secondary)
                        }
                }
                .frame(height: 300)
            }
        } header: {
            Text("Серии по мускулна група")
        } footer: {
            Text("Основната група брои 1 серия, второстепенните 0.5. Загрявките не се броят.")
        }
    }

    private var fatigueSection: some View {
        Section {
            ForEach(recovery, id: \.muscle) { item in
                let status = status(for: item.last)
                HStack {
                    Circle().fill(status.color).frame(width: 10, height: 10)
                    VStack(alignment: .leading) {
                        Text(item.muscle.title)
                        Text(status.text).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(item.weekSets.short) серии/7д").font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Готовност по мускули")
        } footer: {
            Text("Ориентировъчно, не е медицински съвет. Червено: тренирана до 48 ч; жълто: до 72 ч; зелено: готова.")
        }
    }

    private func status(for last: Date?) -> (text: String, color: Color) {
        guard let last else { return ("Още не е тренирана", .gray) }
        let hours = Date.now.timeIntervalSince(last) / 3600
        let ago = hours < 48 ? "преди \(Int(hours)) ч" : "преди \(Int(hours / 24)) дни"
        switch hours {
        case ..<48: return (ago, .red)
        case ..<72: return (ago, .orange)
        default: return (ago, .green)
        }
    }
}


/// Списък по дни: кои дни са силови и кои кардио (за избран период).
struct TrainingDaysView: View {
    let strength: [Date: Int]
    let cardio: [Date: Int]
    @State private var days = 30

    private var rows: [(day: Date, strength: Int, cardio: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let s = strength[day] ?? 0
            let c = cardio[day] ?? 0
            return s + c > 0 ? (day, s, c) : nil
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Период", selection: $days) {
                    Text("Месец").tag(30)
                    Text("3 месеца").tag(90)
                    Text("Година").tag(365)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Силови: \(rows.map(\.strength).reduce(0, +)) · Кардио: \(rows.map(\.cardio).reduce(0, +))")
            }
            Section {
                ForEach(rows, id: \.day) { row in
                    HStack {
                        Text(row.day.formatted(.dateTime.weekday(.abbreviated).day().month(.twoDigits)))
                        Spacer()
                        if row.strength > 0 {
                            Label("Силова\(row.strength > 1 ? " ×\(row.strength)" : "")", systemImage: "figure.strengthtraining.traditional")
                                .foregroundStyle(.green)
                        }
                        if row.cardio > 0 {
                            Label("Кардио\(row.cardio > 1 ? " ×\(row.cardio)" : "")", systemImage: "figure.run")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.callout)
                }
            } header: {
                Text("Дни с тренировка")
            }
        }
        .navigationTitle("Тренировки по дни")
        .navigationBarTitleDisplayMode(.inline)
    }
}
