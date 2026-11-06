import SwiftUI
import SwiftData
import Charts

/// Карти за активността: тренировки за седмица и месец, серия от седмици, 30-дневно тегло и heatmap за 12 месеца.
struct ActivityStatsCard: View {
    @Query private var sessions: [WorkoutSession]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query private var metrics: [DailyMetric]

    @State private var heatDays = 365
    @State private var selectedDay: Date?

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

    /// Силови сесии по дни: от WHOOP/Health. Записите от решетката се ползват само за седмици без данни от устройство
    /// (старите са с дата от началото на седмицата на мезоцикъла, затова най-много една на ден).
    private var strengthByDay: [Date: Int] {
        var result: [Date: Int] = [:]
        var deviceWeeks = Set<Date>()
        for kind in [MetricKind.strengthSessions, .cardioSessions] {
            for point in MetricSeries.series(kind, in: metrics, from: .distantPast) where point.value > 0 {
                deviceWeeks.insert(weekStart(point.day))
            }
        }
        for point in MetricSeries.series(.strengthSessions, in: metrics, from: .distantPast) {
            result[calendar.startOfDay(for: point.day)] = Int(point.value)
        }
        for session in finished where !session.sets.isEmpty && !deviceWeeks.contains(weekStart(session.date)) {
            result[calendar.startOfDay(for: session.date)] = 1
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
                    Text("\(week.start.formatted(.dateTime.day().month(.twoDigits))) – \(lastDay.formatted(.dateTime.day().month(.twoDigits)))" + (isCurrent ? " " + tr("(тази)") : ""))
                        .font(.callout)
                    Spacer()
                    Text(trf("силови %@ · кардио %@", "\(week.strength)", "\(week.cardio)")).font(.callout.bold())
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
                    NavigationLink { TrainingDaysView(strength: strengthByDay, cardio: cardioByDay) } label: {
                        tile("Тази седмица", "\(thisWeekCount)", "figure.strengthtraining.traditional")
                    }
                    NavigationLink { TrainingDaysView(strength: strengthByDay, cardio: cardioByDay) } label: {
                        tile("Този месец", "\(thisMonthCount)", "calendar")
                    }
                }
                GridRow {
                    tile("Серия седмици", "\(weekStreak)", "flame")
                    tile("Тегло 30 дни", weightChange30, "scalemass")
                }
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Тренировки по дни").font(.headline)
            Text("Зелено = ден със силова тренировка; по-наситено = повече минути (WHOOP/Health).")
                .font(.caption)
                .foregroundStyle(.secondary)
            strengthSummary
            Picker("Период", selection: $heatDays) {
                Text("7 дни").tag(7)
                Text("30 дни").tag(30)
                Text("90 дни").tag(90)
                Text("12 месеца").tag(365)
            }
            .pickerStyle(.segmented)
            .onChange(of: heatDays) { selectedDay = nil }
            heatmap
            HStack(spacing: 4) {
                Text("без силова").font(.caption2).foregroundStyle(.secondary)
                RoundedRectangle(cornerRadius: 1.5).fill(color(0)).frame(width: 10, height: 10)
                Text("силова:").font(.caption2).foregroundStyle(.secondary).padding(.leading, 6)
                ForEach([20.0, 45, 75, 100], id: \.self) { minutes in
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
            Label(tr(title), systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(tr(value)).font(.title2.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    /// GitHub-стил: колона = седмица (пон–нед), месеци отгоре, докосване на ден показва какво е тренирано.
    private var heatmap: some View {
        let minutes = minutesByDay
        let strength = strengthByDay
        let cardio = cardioByDay
        let today = calendar.startOfDay(for: .now)
        let first = calendar.date(byAdding: .day, value: -(heatDays - 1), to: today) ?? today
        let start = weekStart(first)
        let weeks = max(1, (calendar.dateComponents([.day], from: start, to: today).day ?? 0) / 7 + 1)
        let cell: CGFloat = heatDays <= 30 ? 26 : (heatDays <= 90 ? 16 : 12)
        let gap: CGFloat = 3
        func day(_ week: Int, _ weekday: Int) -> Date? {
            calendar.date(byAdding: .day, value: week * 7 + weekday, to: start)
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: gap) {
                // Дни от седмицата като в GitHub: пн, ср, пт.
                VStack(alignment: .leading, spacing: gap) {
                    Color.clear.frame(width: 18, height: 12)
                    ForEach(0..<7, id: \.self) { weekday in
                        Text(weekday == 0 ? tr("пн") : weekday == 2 ? tr("ср") : weekday == 4 ? tr("пт") : "")
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                            .frame(width: 18, height: cell, alignment: .leading)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: gap) {
                        ForEach(0..<weeks, id: \.self) { week in
                            VStack(spacing: gap) {
                                // Етикет на месеца над първата седмица, в която започва нов месец.
                                let monday = day(week, 0) ?? start
                                let isNewMonth = week == 0 || calendar.component(.day, from: monday) <= 7
                                Text(isNewMonth ? monday.formatted(.dateTime.month(.abbreviated)) : "")
                                    .font(.system(size: 9)).foregroundStyle(.secondary)
                                    .fixedSize()
                                    .frame(width: cell, height: 12, alignment: .leading)
                                ForEach(0..<7, id: \.self) { weekday in
                                    if let date = day(week, weekday), date >= first, date <= today {
                                        let value = (strength[date] ?? 0) > 0 ? max(minutes[date] ?? 45, 1) : 0
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(color(value))
                                            .frame(width: cell, height: cell)
                                            .overlay {
                                                if selectedDay == date {
                                                    RoundedRectangle(cornerRadius: 2).stroke(Color.primary, lineWidth: 1.5)
                                                }
                                            }
                                            .onTapGesture { selectedDay = selectedDay == date ? nil : date }
                                    } else {
                                        Color.clear.frame(width: cell, height: cell)
                                    }
                                }
                            }
                        }
                    }
                }
                .defaultScrollAnchor(.trailing)
            }
            if let selectedDay {
                dayDetail(selectedDay, minutes: minutes[selectedDay], strength: strength[selectedDay] ?? 0, cardio: cardio[selectedDay] ?? 0)
            } else {
                Text("Докосни ден, за да видиш тренировката.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func dayDetail(_ date: Date, minutes: Double?, strength: Int, cardio: Int) -> some View {
        let names = finished.filter { calendar.isDate($0.date, inSameDayAs: date) }.map(\.title)
        return VStack(alignment: .leading, spacing: 2) {
            Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.caption.bold())
            if strength == 0 && cardio == 0 && names.isEmpty && WorkoutNames.items(on: date).isEmpty {
                Text("Без тренировка").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(trf("силови %@ · кардио %@", "\(strength)", "\(cardio)")
                     + (minutes.map { " · " + trf("%@ мин", "\(Int($0))") } ?? ""))
                    .font(.caption)
                ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                    Label(name, systemImage: "dumbbell").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(WorkoutNames.items(on: date).enumerated()), id: \.offset) { _, item in
                    Label(item.name + " · " + trf("%@ мин", "\(item.minutes)"), systemImage: "figure.run")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
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
                        Text(tr(item.muscle.title))
                        Text(tr(status.text)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(trf("%@ серии/7д", "\(item.weekSets.short)")).font(.caption).foregroundStyle(.secondary)
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
        let ago = hours < 48 ? trf("преди %@ ч", "\(Int(hours))") : trf("преди %@ дни", "\(Int(hours / 24))")
        switch hours {
        case ..<48: return (ago, .red)
        case ..<72: return (ago, .orange)
        default: return (ago, .green)
        }
    }
}


/// Календар по месеци: кои дни са силови (зелено) и кои кардио (оранжево).
struct TrainingDaysView: View {
    let strength: [Date: Int]
    let cardio: [Date: Int]
    @State private var month = Date.now

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    private var monthStart: Date { calendar.dateInterval(of: .month, for: month)?.start ?? month }

    /// Празни клетки до първия ден (седмицата започва от понеделник), после дните на месеца.
    private var cells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        let weekday = calendar.component(.weekday, from: monthStart)
        let blanks = (weekday - calendar.firstWeekday + 7) % 7
        let days = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: monthStart) }
        return Array(repeating: nil, count: blanks) + days
    }

    private var monthDays: [Date] { cells.compactMap { $0 }.filter { (strength[$0] ?? 0) + (cardio[$0] ?? 0) > 0 } }

    private func change(_ months: Int) {
        month = calendar.date(byAdding: .month, value: months, to: monthStart) ?? month
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Button { change(-1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(monthStart.formatted(.dateTime.month(.wide).year())).font(.headline)
                    Spacer()
                    Button { change(1) } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.borderless)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                    ForEach(["пн", "вт", "ср", "чт", "пт", "сб", "нд"], id: \.self) { name in
                        Text(tr(name)).font(.caption2).foregroundStyle(.secondary)
                    }
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                        if let day {
                            dayCell(day)
                        } else {
                            Color.clear.frame(height: 40)
                        }
                    }
                }
                HStack(spacing: 12) {
                    Label("Силова", systemImage: "circle.fill").foregroundStyle(.green)
                    Label("Кардио", systemImage: "circle.fill").foregroundStyle(.orange)
                }
                .font(.caption)
            } footer: {
                Text(trf("Силови: %@ · Кардио: %@", "\(monthDays.map { strength[$0] ?? 0 }.reduce(0, +))", "\(monthDays.map { cardio[$0] ?? 0 }.reduce(0, +))"))
            }
            Section {
                ForEach(monthDays.reversed(), id: \.self) { day in
                    HStack {
                        Text(day.formatted(.dateTime.weekday(.abbreviated).day().month(.twoDigits)))
                        Spacer()
                        if let count = strength[day], count > 0 {
                            Label(tr("Силова") + (count > 1 ? " ×\(count)" : ""), systemImage: "figure.strengthtraining.traditional")
                                .foregroundStyle(.green)
                        }
                        if let count = cardio[day], count > 0 {
                            Label(tr("Кардио") + (count > 1 ? " ×\(count)" : ""), systemImage: "figure.run")
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

    private func dayCell(_ day: Date) -> some View {
        let hasStrength = (strength[day] ?? 0) > 0
        let hasCardio = (cardio[day] ?? 0) > 0
        return VStack(spacing: 3) {
            Text("\(calendar.component(.day, from: day))")
                .font(.callout)
                .foregroundStyle(calendar.isDateInToday(day) ? Color.accentColor : Color.primary)
            HStack(spacing: 3) {
                Circle().fill(hasStrength ? Color.green : Color.clear).frame(width: 7, height: 7)
                Circle().fill(hasCardio ? Color.orange : Color.clear).frame(width: 7, height: 7)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 40)
        .background((hasStrength || hasCardio) ? Color.secondary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
    }
}
