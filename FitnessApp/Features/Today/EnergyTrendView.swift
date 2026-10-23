import SwiftUI
import SwiftData
import Charts

/// Как се движи дневният разход: формула, данни от устройствата и реален (по теглото и приема).
struct EnergyTrendView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query(sort: \FoodEntry.date) private var foods: [FoodEntry]
    @Query private var metrics: [DailyMetric]
    @State private var showingApply = false
    /// Храна от Apple Health (напр. MyFitnessPal), събира се с записаната в приложението.
    var healthFood: [Date: NutritionDay] = [:]

    private var weeks: [EnergyModel.WeekPoint] {
        guard let profile = profiles.first else { return [] }
        let params = EnergyModel.Params(sex: profile.sex, heightCm: profile.heightCm, age: profile.age,
                                        activityFactor: profile.activityFactor, bodyFat: profile.bodyFatPercent)
        return EnergyModel.weeks(params: params,
                                 weights: weights.map { (date: $0.date, kg: $0.kg) },
                                 intakeByDay: intakeByDay, activeByDay: activeByDay)
    }

    private var intakeByDay: [Date: Double] {
        var result: [Date: Double] = [:]
        for food in foods { result[Calendar.current.startOfDay(for: food.date), default: 0] += food.kcal }
        for (day, value) in healthFood { result[day, default: 0] += value.kcal }
        return result
    }

    /// Активни калории по дни; при два източника за един ден се взема Apple Health.
    private var activeByDay: [Date: Double] {
        var result: [Date: Double] = [:]
        var fromHealth: Set<Date> = []
        for metric in metrics where metric.kind == .activeKcal {
            let day = Calendar.current.startOfDay(for: metric.day)
            let isHealth = metric.sourceRaw == MetricSource.health.rawValue
            if isHealth || !fromHealth.contains(day) {
                result[day] = metric.value
                if isHealth { fromHealth.insert(day) }
            }
        }
        return result
    }

    private var latest: EnergyModel.WeekPoint? { weeks.last }

    private var latestReal: Double? { weeks.reversed().compactMap(\.real).first }
    private var latestFormula: Double? { weeks.reversed().compactMap(\.formula).first }
    private var latestBMR: Double? { weeks.reversed().compactMap(\.bmr).first }
    private var latestDevice: Double? { weeks.reversed().compactMap(\.device).first }

    private func text(_ value: Double?) -> String {
        guard let value else { return "няма данни" }
        return "\(Int(value.rounded())) ккал"
    }

    /// Очаквана промяна в кг за седмицата: (прием − разход с активност, иначе дневен разход) × 7 / 7700.
    private func expectedChange(_ week: EnergyModel.WeekPoint) -> Double? {
        guard let intake = week.intake, let expenditure = week.device ?? week.formula else { return nil }
        return (intake - expenditure) * 7 / EnergyModel.kcalPerKg
    }

    private func weightText(_ week: EnergyModel.WeekPoint) -> String {
        let kg = week.kg.map { $0.formatted(.number.precision(.fractionLength(0...1))) + " кг" } ?? "–"
        return "Тегло \(kg) · прием \(text(week.intake))"
    }

    private func changeText(_ change: Double) -> String {
        let sign = change >= 0 ? "+" : "−"
        let value = abs(change).formatted(.number.precision(.fractionLength(2)))
        return "Очаквана промяна по прием и разход: \(sign)\(value) кг"
    }

    private func weekRow(_ week: EnergyModel.WeekPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Седмица от \(week.weekStart.formatted(.dateTime.day().month(.abbreviated)))")
                .font(.subheadline.weight(.semibold))
            Text(weightText(week))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(valuesText(week))
                .font(.caption)
            if let change = expectedChange(week) {
                Text(changeText(change))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func valuesText(_ week: EnergyModel.WeekPoint) -> String {
        var result = "BMR \(text(week.bmr)) · общ \(text(week.device ?? week.formula))"
        if let real = week.real { result += " · реален \(text(real))" }
        return result
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Базов обмен (BMR)", value: text(latestBMR))
                LabeledContent("Общ разход за деня", value: text(latestDevice ?? latestFormula))
                if let real = latestReal, let total = latestDevice ?? latestFormula, total > 0 {
                    LabeledContent("Реален (по тегло и храна)", value: text(real))
                    let percent = (real - total) / total * 100
                    LabeledContent("Реален спрямо общия",
                                   value: "\(percent >= 0 ? "+" : "")\(percent.formatted(.number.precision(.fractionLength(0)))) %")
                }
            } header: {
                Text("Сега")
            } footer: {
                Text("Базов обмен (BMR): колко калории гориш за 24 ч в пълен покой (по постната маса, ако има % мазнини). Общ разход: BMR + движение и тренировки (активни калории от часовника/телефона) + ~10% за храносмилане; ако няма активни калории, BMR × коефициента на активност от профила. Реален: изчислен от промяната на теглото и записаната храна, след поне 10 дни с храна и редовно тегло. Средно на ден за седмицата. Ориентировъчно, не е медицински съвет.")
            }

            if let real = latestReal, let profile = profiles.first, let kg = weights.last?.kg {
                let bmr = BodyMath.bmr(sex: profile.sex, kg: kg, cm: profile.heightCm, age: profile.age, bodyFat: profile.bodyFatPercent)
                let suggested = min(max(real / bmr, 1.2), 2.2)
                Section {
                    LabeledContent("Сега в профила", value: profile.activityFactor.formatted(.number.precision(.fractionLength(0...2))))
                    LabeledContent("По реалните данни", value: suggested.formatted(.number.precision(.fractionLength(0...2))))
                    Button("Приложи към профила") { showingApply = true }
                } header: {
                    Text("Калибриране")
                } footer: {
                    Text("Коефициентът на активност определя нормите за калории. Ако реалният разход се държи стабилно 3–4 седмици, можеш да го коригираш.")
                }
            }

            Section {
                if weeks.contains(where: { $0.bmr != nil }) {
                    Chart {
                        ForEach(weeks) { week in
                            if let value = week.bmr {
                                LineMark(x: .value("Седмица", week.weekStart), y: .value("ккал", value),
                                         series: .value("Метод", "BMR"))
                                    .foregroundStyle(by: .value("Метод", "BMR"))
                            }
                            if let value = week.device ?? week.formula {
                                LineMark(x: .value("Седмица", week.weekStart), y: .value("ккал", value),
                                         series: .value("Метод", "Общ"))
                                    .foregroundStyle(by: .value("Метод", "Общ"))
                            }
                            if let value = week.real {
                                LineMark(x: .value("Седмица", week.weekStart), y: .value("ккал", value),
                                         series: .value("Метод", "Реален"))
                                    .foregroundStyle(by: .value("Метод", "Реален"))
                            }
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartScrub(weeks.map {
                        ScrubPoint(date: $0.weekStart, value: $0.device ?? $0.formula ?? $0.real ?? 0,
                                   text: "Седмица от \(scrubDate($0.weekStart)): " + valuesText($0))
                    })
                    .padding(.top, 24)
                    .frame(height: 230)
                } else {
                    Text("Попълни профила и въведи тегло, за да се появи графиката.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Средно на ден, по седмици (ккал)")
            }

            Section("Седмиците") {
                ForEach(weeks.reversed()) { week in
                    weekRow(week)
                }
            }
        }
        .navigationTitle("Разход: тенденция")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Да сложа ли новия коефициент в профила?", isPresented: $showingApply, titleVisibility: .visible) {
            Button("Приложи") { applySuggested() }
            Button("Отказ", role: .cancel) {}
        }
    }

    private func applySuggested() {
        guard let real = latestReal, let profile = profiles.first, let kg = weights.last?.kg else { return }
        let bmr = BodyMath.bmr(sex: profile.sex, kg: kg, cm: profile.heightCm, age: profile.age, bodyFat: profile.bodyFatPercent)
        profile.activityFactor = (min(max(real / bmr, 1.2), 2.2) * 100).rounded() / 100
    }
}
