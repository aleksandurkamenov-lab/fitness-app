import SwiftUI
import SwiftData

/// Днес: сън, възстановяване и натоварване от Apple Health, в духа на WHOOP.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @State private var health = HealthService()
    @State private var whoop = WhoopService.shared
    @State private var healthFood: [Date: NutritionDay] = [:]
    @Query private var profiles: [UserProfile]
    @Query(sort: \FoodEntry.date) private var foods: [FoodEntry]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query(sort: \MeasurementEntry.date) private var measurements: [MeasurementEntry]
    @Query(sort: \DailyMetric.day, order: .reverse) private var storedMetrics: [DailyMetric]
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    private var age: Int { profiles.first?.age ?? 30 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !health.isAvailable {
                        notice("Apple Health не е достъпно на това устройство.")
                    } else if !health.wasRequested && !whoop.isConnected {
                        connectCard
                    } else if let snapshot = health.snapshot ?? (whoop.snapshot != nil ? HealthSnapshot() : nil) {
                        content(snapshot)
                    } else {
                        ProgressView("Зареждам от Apple Health…")
                            .padding(.top, 60)
                    }
                    if let error = health.errorText {
                        notice(error)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Днес")
            .profileButton()
            .refreshable {
                refreshBodyFat()
                await health.load(age: age)
                await whoop.load()
                await syncHistory()
                healthFood = await health.nutrition(days: 28)
            }
            .task {
                refreshBodyFat()
                if health.wasRequested { await health.load(age: age) }
                if whoop.isConnected { await whoop.load() }
                await syncHistory()
                if health.wasRequested { healthFood = await health.nutrition(days: 28) }
            }
        }
    }

    private func refreshBodyFat() {
        if let profile = profiles.first {
            BodyMath.refreshBodyFat(profile: profile, weights: weights, measurements: measurements)
        }
    }

    /// Записва историята на показателите и внася старото тегло от Health.
    private func syncHistory() async {
        var points: [MetricPoint] = []
        if health.wasRequested {
            points += await health.history(days: 90)
            HistorySync.importWeights(await health.weightHistory(), in: context)
        }
        if whoop.isConnected { points += await whoop.history() }
        HistorySync.store(points, in: context)
    }

    // MARK: Връзка

    private var connectCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 44))
                .foregroundStyle(.red)
            Text("Свържи Apple Health")
                .font(.title3.weight(.semibold))
            Text("Приложението чете сън, пулс в покой, дишане, SpO₂, крачки и тренировки, за да смята сън, възстановяване и натоварване. Нищо не се записва обратно и нищо не напуска телефона.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await health.requestAccess() }
            } label: {
                Text("Свържи")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Съдържание

    @ViewBuilder
    private func content(_ healthSnapshot: HealthSnapshot) -> some View {
        let w = whoop.snapshot
        let s = merged(healthSnapshot, with: w)
        let ownSleep = s.asleepHours.map { RecoveryMath.sleepScore(asleepHours: $0, inBedHours: s.inBedHours) }
        let sleep = w?.sleepPerformance ?? ownSleep
        let ownRecovery = RecoveryMath.recovery(.init(
            hrv: s.hrv, hrvBaseline: s.hrvBaseline,
            rhr: s.rhr, rhrBaseline: s.rhrBaseline,
            respiratory: s.respiratory, respiratoryBaseline: s.respiratoryBaseline,
            sleepScore: ownSleep))
        let recovery = w?.recoveryScore ?? ownRecovery
        let ownStrain: Double? = s.heartRates.isEmpty ? nil
            : RecoveryMath.strain(heartRates: s.heartRates, restingHR: s.rhr ?? 60, age: age)
        let strain = w?.strain ?? ownStrain

        HStack(spacing: 12) {
            link(.metric(.sleepPerformance)) {
                RingView(title: "Сън", valueText: sleep.map { "\(Int($0))%" } ?? "–",
                         progress: (sleep ?? 0) / 100, color: .indigo)
            }
            link(.metric(.recovery)) {
                RingView(title: "Възстановяване", valueText: recovery.map { "\(Int($0))%" } ?? "–",
                         progress: (recovery ?? 0) / 100, color: recoveryColor(recovery))
            }
            link(.metric(.strain)) {
                RingView(title: "Натоварване", valueText: strain.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "–",
                         progress: (strain ?? 0) / 21, color: .blue)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))

        NavigationLink {
            TrendsView()
        } label: {
            HStack {
                Label("Тенденции и графики", systemImage: "chart.xyaxis.line")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)

        if recovery == nil {
            notice("Възстановяването се смята, когато има поне 7 дни пулс в покой, дишане или HRV в Apple Health плюс сън. Дотогава показваме само сън и натоварване.")
        }

        healthMonitor(s)
        dashboard(s)
        energyCard(s)
        myDay(s)

        if w != nil {
            notice("Сън, възстановяване, натоварване, HRV и пулс в покой са от WHOOP. Крачките и тренировките са от Apple Health. Не е медицински съвет.")
        } else {
            notice("Оценките са наши, ориентировъчни изчисления от данните в Apple Health. Не са оценките на WHOOP или Polar и не са медицински съвет." + (s.sleepSource.map { " Сънят е от: \($0)." } ?? ""))
        }
    }

    /// Данните на WHOOP имат предимство пред Apple Health за сън, пулс и HRV.
    private func merged(_ health: HealthSnapshot, with w: WhoopSnapshot?) -> HealthSnapshot {
        var h = health
        guard let w else { return withStoredFallback(h) }
        h.hrv = w.hrv ?? h.hrv
        h.rhr = w.rhr ?? h.rhr
        h.respiratory = w.respiratory ?? h.respiratory
        h.oxygen = w.spo2 ?? h.oxygen
        h.skinTempDelta = w.skinTempDelta ?? h.skinTempDelta
        h.hrvBaseline = w.hrvBaseline ?? h.hrvBaseline
        h.rhrBaseline = w.rhrBaseline ?? h.rhrBaseline
        h.respiratoryBaseline = w.respiratoryBaseline ?? h.respiratoryBaseline
        h.oxygenBaseline = w.spo2Baseline ?? h.oxygenBaseline
        h.asleepHours = w.asleepHours ?? h.asleepHours
        h.inBedHours = w.inBedHours ?? h.inBedHours
        h.sleepStart = w.sleepStart ?? h.sleepStart
        h.sleepEnd = w.sleepEnd ?? h.sleepEnd
        h.sleepSource = "WHOOP"
        h.whoopTotalKcal = w.cycleKcal
        // Тренировки от WHOOP, без повторения с тези от Health със същото начало.
        let known = Set(h.workouts.map { Int($0.start.timeIntervalSince1970 / 300) })
        h.workouts += w.workouts.filter { !known.contains(Int($0.start.timeIntervalSince1970 / 300)) }
        return withStoredFallback(h)
    }

    /// Ако източникът не върне стойност (грешка в мрежата, още няма оценка), показваме последната записана от последните 3 дни.
    private func withStoredFallback(_ snapshot: HealthSnapshot) -> HealthSnapshot {
        var h = snapshot
        let cutoff = Calendar.current.date(byAdding: .day, value: -3, to: .now) ?? .now
        func latest(_ kind: MetricKind) -> Double? {
            storedMetrics.first { $0.kindRaw == kind.rawValue && $0.day >= cutoff }?.value
        }
        h.hrv = h.hrv ?? latest(.hrv)
        h.oxygen = h.oxygen ?? latest(.spo2)
        h.rhr = h.rhr ?? latest(.rhr)
        h.respiratory = h.respiratory ?? latest(.respiratory)
        return h
    }

    /// Натискане върху показател отваря подробностите му (7 / 30 / 90 дни).
    private func link<Label: View>(_ target: TrendTarget, @ViewBuilder label: () -> Label) -> some View {
        NavigationLink {
            MetricDetailView(target: target)
        } label: {
            label()
        }
        .buttonStyle(.plain)
    }

    private func recoveryColor(_ value: Double?) -> Color {
        guard let value else { return .gray }
        return value < 34 ? .red : (value < 67 ? .yellow : .green)
    }

    // MARK: Монитор на здравето

    private func healthMonitor(_ s: HealthSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Монитор на здравето").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                link(.metric(.rhr)) {
                    MetricTile(title: "Пулс в покой", value: s.rhr, unit: "уд./мин", digits: 0,
                               baseline: s.rhrBaseline, missing: "няма данни")
                }
                link(.metric(.hrv)) {
                    MetricTile(title: "HRV", value: s.hrv, unit: "мс", digits: 0,
                               baseline: s.hrvBaseline,
                               missing: "свържи WHOOP (Профил → Устройства)")
                }
                link(.metric(.respiratory)) {
                    MetricTile(title: "Дишане", value: s.respiratory, unit: "вд./мин", digits: 1,
                               baseline: s.respiratoryBaseline, missing: "няма данни")
                }
                link(.metric(.spo2)) {
                    MetricTile(title: "SpO₂", value: s.oxygen, unit: "%", digits: 0,
                               baseline: s.oxygenBaseline,
                               missing: "няма данни")
                }
                if let delta = s.skinTempDelta {
                    link(.metric(.skinTemp)) {
                        MetricTile(title: "Температура на кожата", value: delta, unit: "°C от нормата", digits: 1,
                                   baseline: nil, missing: "", signed: true)
                    }
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Табло

    private func dashboard(_ s: HealthSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Таблото ми").font(.headline)
            link(.metric(.steps)) {
                DashboardRow(title: "Крачки", icon: "figure.walk", value: s.steps, average: s.avgSteps, unit: "")
            }
            link(.metric(.activeKcal)) {
                DashboardRow(title: "Активни калории", icon: "flame", value: s.activeKcal, average: s.avgActiveKcal, unit: "ккал")
            }
            link(.metric(.hrv)) {
                DashboardRow(title: "HRV", icon: "waveform.path.ecg", value: s.hrv, average: s.hrvBaseline?.mean, unit: "мс")
            }
            link(.metric(.rhr)) {
                DashboardRow(title: "Пулс в покой", icon: "heart", value: s.rhr, average: s.rhrBaseline?.mean, unit: "уд./мин")
            }
            link(.metric(.sleepHours)) {
                DashboardRow(title: "Сън", icon: "moon.zzz", value: s.asleepHours, average: nil, unit: "ч", digits: 1)
            }
            if let weight = weights.last?.kg {
                let previous = weights.dropLast().last?.kg
                link(.weight) {
                    DashboardRow(title: "Тегло", icon: "scalemass", value: weight, average: previous, unit: "кг", digits: 1)
                }
            }
            if let vo2 = s.vo2Max {
                DashboardRow(title: "VO₂ max", icon: "lungs", value: vo2, average: nil, unit: "", digits: 0)
            }
            Text("Сивото число е средното (за теглото: предишното измерване). Натисни показател за 7 / 30 / 90 дни.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Енергиен баланс

    private func energyCard(_ s: HealthSnapshot) -> some View {
        let profile = profiles.first
        let kg = weights.last?.kg
        let intake = foods.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.kcal }
            + (healthFood[Calendar.current.startOfDay(for: .now)]?.kcal ?? 0)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Енергиен баланс днес").font(.headline)
            if let profile, let kg {
                let day = BodyMath.dayEnergy(profile: profile, kg: kg, intake: intake,
                                             activeKcal: s.activeKcal, whoopTotal: s.whoopTotalKcal)
                energyRow("Дневен разход (очакван за целия ден)", day.projectedTotal, bold: true)
                energyRow("Базов обмен за деня", day.fullDayBasal)
                energyRow("Активни до сега (крачки, тренировки, кардио)", day.active)
                let workoutKcal = s.workouts.reduce(0) { $0 + ($1.kcal ?? 0) }
                if workoutKcal > 0 { energyRow("от тях тренировки и кардио", workoutKcal) }
                if let steps = s.steps { energyRow("Крачки днес", steps, unit: " стъпки") }
                Divider()
                energyRow("Базов обмен до сега", day.basal)
                energyRow("Разход до сега", day.total, bold: true)
                energyRow("Прием (храна и Apple Health)", day.intake)
                HStack {
                    Text("Баланс до сега").fontWeight(.semibold)
                    Spacer()
                    let value = Int(day.balance.rounded())
                    Text(value >= 0 ? "+\(value) ккал излишък" : "\(value) ккал дефицит")
                        .fontWeight(.semibold)
                        .foregroundStyle(value >= 0 ? Color.orange : Color.green)
                }
                Text(day.fromWhoop
                     ? "Разходът е от WHOOP (цялата енергия на деня). Приемът е от записаната храна."
                     : "Базовият обмен е по формула (пол, тегло, ръст, възраст), активните калории са от Apple Health (крачки, тренировки, кардио, пулс). Приемът е от записаната храна. Ориентировъчно.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                NavigationLink {
                    EnergyTrendView(healthFood: healthFood)
                } label: {
                    Label("Тенденция и точност на разхода", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.subheadline)
                }
            } else {
                Text("Попълни профила (пол, ръст, възраст) и въведи тегло, за да се смята разходът.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func energyRow(_ title: String, _ value: Double, bold: Bool = false, unit: String = " ккал") -> some View {
        HStack {
            Text(title).fontWeight(bold ? .semibold : .regular)
            Spacer()
            Text("\(Int(value.rounded()))\(unit)").fontWeight(bold ? .semibold : .regular).monospacedDigit()
        }
    }

    // MARK: Моят ден

    private func myDay(_ s: HealthSnapshot) -> some View {
        let appToday = sessions.filter { $0.isFinished && Calendar.current.isDateInToday($0.date) }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Моят ден").font(.headline)
            if let start = s.sleepStart, let end = s.sleepEnd, let hours = s.asleepHours {
                dayRow(icon: "moon.zzz", title: "Сън",
                       detail: "\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))",
                       trailing: "\(Int(hours))ч \(Int((hours * 60).truncatingRemainder(dividingBy: 60)))м")
            }
            ForEach(appToday) { session in
                dayRow(icon: "dumbbell", title: session.title,
                       detail: session.date.formatted(date: .omitted, time: .shortened),
                       trailing: "\(WorkoutMath.totalVolume(session.sets).short) кг обем")
            }
            ForEach(s.workouts) { workout in
                dayRow(icon: "figure.run", title: workout.name,
                       detail: workout.start.formatted(date: .omitted, time: .shortened),
                       trailing: "\(Int(workout.minutes)) мин" + (workout.kcal.map { " · \(Int($0)) ккал" } ?? ""))
            }
            if s.sleepStart == nil && appToday.isEmpty && s.workouts.isEmpty {
                Text("Още няма записани събития за днес.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func dayRow(icon: String, title: String, detail: String, trailing: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 28)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(trailing).font(.subheadline)
        }
    }
}

// MARK: Компоненти

private struct RingView: View {
    let title: String
    let valueText: String
    let progress: Double
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: max(0.001, min(progress, 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(valueText)
                    .font(.title3.weight(.bold))
                    .minimumScaleFactor(0.6)
            }
            .frame(width: 84, height: 84)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MetricTile: View {
    let title: String
    let value: Double?
    let unit: String
    let digits: Int
    let baseline: RecoveryMath.Baseline?
    let missing: String
    var signed = false

    private var status: RecoveryMath.Status? {
        value.flatMap { RecoveryMath.status($0, baseline: baseline) }
    }

    private var statusColor: Color {
        switch status {
        case .normal: .green
        case .high, .low: .orange
        case nil: .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if let value {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text((signed && value > 0 ? "+" : "") + value.formatted(.number.precision(.fractionLength(digits))))
                        .font(.title2.weight(.bold))
                    Text(unit).font(.caption2).foregroundStyle(.secondary)
                }
                if let status {
                    Text(status.title).font(.caption2.weight(.semibold)).foregroundStyle(statusColor)
                }
            } else {
                Text("–").font(.title2.weight(.bold))
                Text(missing).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct DashboardRow: View {
    let title: String
    let icon: String
    let value: Double?
    let average: Double?
    let unit: String
    var digits = 0

    private func text(_ number: Double) -> String {
        number.formatted(.number.precision(.fractionLength(digits)))
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 28).foregroundStyle(.secondary)
            Text(title).font(.subheadline)
            Spacer()
            VStack(alignment: .trailing) {
                HStack(spacing: 4) {
                    Text(value.map(text) ?? "–").font(.headline)
                    if let value, let average {
                        Image(systemName: value >= average ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(.secondary) }
                }
                if let average {
                    Text(text(average)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
