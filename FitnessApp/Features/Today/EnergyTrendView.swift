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
                                        activityFactor: profile.activityFactor)
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
    private var latestDevice: Double? { weeks.reversed().compactMap(\.device).first }

    private func text(_ value: Double?) -> String {
        guard let value else { return "няма данни" }
        return "\(Int(value.rounded())) ккал"
    }

    var body: some View {
        List {
            Section {
                LabeledContent("По формулата", value: text(latestFormula))
                LabeledContent("От устройствата", value: text(latestDevice))
                LabeledContent("Реален (тегло и прием)", value: text(latestReal))
                if let real = latestReal, let formula = latestFormula, formula > 0 {
                    let percent = (real - formula) / formula * 100
                    LabeledContent("Реален спрямо формулата",
                                   value: "\(percent >= 0 ? "+" : "")\(percent.formatted(.number.precision(.fractionLength(0)))) %")
                }
            } header: {
                Text("Сега")
            } footer: {
                Text("Формула: Mifflin-St Jeor × коефициент на активност. Устройства: базов обмен + активни калории от Apple Health, с ~10% термичен ефект. Реален: среден записан прием минус промяната в теглото × 7700 ккал/кг за последните 3 седмици (нужни са поне 10 дни със записана храна и редовно тегло). Реалният е най-точният, ако записваш храната си. Ориентировъчно.")
            }

            if let real = latestReal, let profile = profiles.first, let kg = weights.last?.kg {
                let bmr = BodyMath.bmr(sex: profile.sex, kg: kg, cm: profile.heightCm, age: profile.age)
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
                if weeks.contains(where: { $0.formula != nil }) {
                    Chart {
                        ForEach(weeks) { week in
                            if let value = week.formula {
                                LineMark(x: .value("Седмица", week.weekStart), y: .value("ккал", value),
                                         series: .value("Метод", "Формула"))
                                    .foregroundStyle(by: .value("Метод", "Формула"))
                            }
                            if let value = week.device {
                                LineMark(x: .value("Седмица", week.weekStart), y: .value("ккал", value),
                                         series: .value("Метод", "Устройства"))
                                    .foregroundStyle(by: .value("Метод", "Устройства"))
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
                        ScrubPoint(date: $0.weekStart, value: $0.formula ?? $0.device ?? $0.real ?? 0,
                                   text: "Седмица от \(scrubDate($0.weekStart)): формула \(text($0.formula)) · устройства \(text($0.device)) · реален \(text($0.real))")
                    })
                    .padding(.top, 24)
                    .frame(height: 230)
                } else {
                    Text("Попълни профила и въведи тегло, за да се появи графиката.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("По седмици")
            }

            Section("Седмиците") {
                ForEach(weeks.reversed()) { week in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Седмица от \(week.weekStart.formatted(.dateTime.day().month(.abbreviated)))")
                            .font(.subheadline.weight(.semibold))
                        Text("Тегло \(week.kg.map { $0.formatted(.number.precision(.fractionLength(0...1))) + " кг" } ?? "–") · прием \(text(week.intake))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Формула \(text(week.formula)) · устройства \(text(week.device)) · реален \(text(week.real))")
                            .font(.caption)
                    }
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
        let bmr = BodyMath.bmr(sex: profile.sex, kg: kg, cm: profile.heightCm, age: profile.age)
        profile.activityFactor = (min(max(real / bmr, 1.2), 2.2) * 100).rounded() / 100
    }
}
