import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    var body: some View {
        Group {
            if let profile = profiles.first {
                ProfileForm(profile: profile)
            } else {
                ProgressView()
                    .onAppear { context.insert(UserProfile()) }
            }
        }
        .navigationTitle("Профил")
        .keyboardDoneButton()
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ProfileForm: View {
    @Bindable var profile: UserProfile

    private let rates: [Double] = [0.1, 0.25, 0.5, 0.75, 1.0]

    private let activities: [(String, Double)] = [
        ("Почти без движение", 1.2),
        ("Лека (1–3 тренировки)", 1.375),
        ("Умерена (3–5 тренировки)", 1.55),
        ("Висока (6–7 тренировки)", 1.725),
    ]

    var body: some View {
        Form {
            Section("За мен") {
                Picker("Пол", selection: $profile.sex) {
                    ForEach(Sex.allCases) { Text($0.title).tag($0) }
                }
                DatePicker("Рождена дата", selection: $profile.birthDate, in: ...Date.now, displayedComponents: .date)
                HStack {
                    Text("Ръст (см)")
                    Spacer()
                    TextField("см", value: $profile.heightCm, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
                Picker("Активност", selection: $profile.activityFactor) {
                    ForEach(activities, id: \.1) { Text($0.0).tag($0.1) }
                }
            }

            Section("Цел") {
                Picker("Цел", selection: $profile.goal) {
                    ForEach(GoalKind.allCases) { Text($0.title).tag($0) }
                }
                if profile.goal == .lose {
                    Picker("Темпо на сваляне", selection: $profile.lossRateKg) {
                        ForEach(rates, id: \.self) { Text("\($0.formatted(.number.precision(.fractionLength(0...2)))) кг седмично").tag($0) }
                    }
                } else if profile.goal == .gain {
                    Picker("Темпо на качване", selection: $profile.gainRateKg) {
                        ForEach(rates, id: \.self) { Text("\($0.formatted(.number.precision(.fractionLength(0...2)))) кг седмично").tag($0) }
                    }
                }
            }

            Section("Макроси (г на кг тегло)") {
                Stepper("Белтък при дефицит: \(profile.proteinLoseGPerKg.short)",
                        value: $profile.proteinLoseGPerKg, in: 1.0...3.5, step: 0.1)
                Stepper("Белтък при бълк и поддръжка: \(profile.proteinOtherGPerKg.short)",
                        value: $profile.proteinOtherGPerKg, in: 1.0...3.5, step: 0.1)
                Stepper("Мазнини минимум: \(profile.fatMinGPerKg.short)",
                        value: $profile.fatMinGPerKg, in: 0.4...2.0, step: 0.1)
            }

            Section {
            } footer: {
                Text("Калкулаторите са ориентировъчни и не са медицински съвет.")
            }
        }
    }
}

/// Калории и макроси от целта, които може да се променят ръчно.
private struct MacroEditor: View {
    @Bindable var profile: UserProfile
    let targets: BodyMath.Targets
    let kg: Double
    let sessions: [WorkoutSession]
    let weights: [WeightEntry]

    private func binding(_ keyPath: ReferenceWritableKeyPath<UserProfile, Double>, auto: Double) -> Binding<Double?> {
        Binding(
            get: {
                let custom = profile[keyPath: keyPath]
                return (custom > 0 ? custom : auto).rounded()
            },
            set: { profile[keyPath: keyPath] = max($0 ?? 0, 0) }
        )
    }

    private var protein: Double { profile.customProteinG > 0 ? profile.customProteinG : targets.protein }
    private var fat: Double { profile.customFatG > 0 ? profile.customFatG : targets.fat }
    private var carbs: Double { profile.customCarbsG > 0 ? profile.customCarbsG : targets.carbs }
    private var kcal: Double { protein * 4 + carbs * 4 + fat * 9 }
    private var isCustom: Bool { profile.customProteinG > 0 || profile.customFatG > 0 || profile.customCarbsG > 0 }

    private func row(_ title: String, _ value: Binding<Double?>, unit: String = "г") -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("г", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .textFieldStyle(.roundedBorder)
            Text(unit)
        }
    }

    var body: some View {
        Section("Цел: \(profile.goal.title)") {
            LabeledContent("Калории от целта", value: "\(Int(targets.kcal)) ккал")
            row("Белтък", binding(\.customProteinG, auto: targets.protein))
            row("Мазнини", binding(\.customFatG, auto: targets.fat))
            row("Въглехидрати", binding(\.customCarbsG, auto: targets.carbs))
            LabeledContent("Калории от макросите", value: "\(Int(kcal)) ккал")
            if isCustom {
                LabeledContent("Разлика спрямо целта", value: "\(Int(kcal - targets.kcal)) ккал")
                Button("Върни автоматичните стойности", role: .destructive) {
                    profile.customProteinG = 0
                    profile.customFatG = 0
                    profile.customCarbsG = 0
                }
            }
        }
        .keyboardDoneButton()

        let forecast = BodyMath.forecast(profile: profile, kg: kg, intake: kcal, sessions: sessions)
        Section("Прогноза по твоите макроси") {
            row("Средни крачки на ден", Binding<Double?>(
                get: { profile.avgDailySteps },
                set: { profile.avgDailySteps = max($0 ?? 0, 0) }
            ), unit: "")
            row("Кардио на седмица", Binding<Double?>(
                get: { profile.weeklyCardioMinutes },
                set: { profile.weeklyCardioMinutes = max($0 ?? 0, 0) }
            ), unit: "мин")
            LabeledContent("Прием", value: "\(Int(forecast.intake)) ккал")
            LabeledContent("Базов разход", value: "\(Int(forecast.baseKcal)) ккал")
            LabeledContent("Крачки", value: "+\(Int(forecast.stepsKcal)) ккал")
            LabeledContent("Тренировки", value: "+\(Int(forecast.trainingKcal)) ккал")
            LabeledContent("Кардио", value: "+\(Int(forecast.cardioKcal)) ккал")
            LabeledContent("Общ разход", value: "\(Int(forecast.expenditure)) ккал")
            LabeledContent("Очаквана промяна", value: verdict(forecast.weeklyChangeKg))
            if let actual = BodyMath.actualWeeklyChange(weights) {
                LabeledContent("Реален тренд (21 дни)", value: "\(actual > 0 ? "+" : "")\(actual.formatted(.number.precision(.fractionLength(0...2)))) кг/седм.")
            }
        } footer: {
            Text("Ориентировъчно, грешката е 10–15%. Тренировките се смятат от записаните сесии, крачките и кардиото са ръчни, докато не ги вземем от Apple Health. Сънят още не влиза в сметката: той показва възстановяване, не изгаря калории. Реалният тренд от теглото е по-точен от прогнозата.")
        }
    }

    private func verdict(_ change: Double) -> String {
        let text = abs(change).formatted(.number.precision(.fractionLength(0...2)))
        if abs(change) < 0.1 { return "стабилно тегло" }
        return change < 0 ? "сваляш ~\(text) кг/седм." : "качваш ~\(text) кг/седм."
    }
}

struct CalculatorsView: View {
    @Query private var profiles: [UserProfile]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query(sort: \MeasurementEntry.date) private var measurements: [MeasurementEntry]
    @Query private var sessions: [WorkoutSession]

    private func latest(_ kind: MeasurementKind) -> Double? {
        measurements.last { $0.kind == kind }?.cm
    }

    private func value(_ number: Double?, _ unit: String) -> String {
        number.map { "\($0.short) \(unit)" } ?? "няма данни"
    }

    var body: some View {
        List {
            if let profile = profiles.first, let kg = weights.last?.kg {
                let bmi = BodyMath.bmi(kg: kg, cm: profile.heightCm)
                let navy = latest(.waist).flatMap { waist in
                    latest(.neck).flatMap { neck in
                        BodyMath.navyBodyFat(sex: profile.sex, heightCm: profile.heightCm,
                                             waist: waist, neck: neck, hips: latest(.hips))
                    }
                }
                let rfm = latest(.waist).flatMap { BodyMath.rfm(sex: profile.sex, heightCm: profile.heightCm, waist: $0) }
                let scaleFat = weights.last?.bodyFatPercent

                Section("Тяло") {
                    LabeledContent("ИТМ", value: value(bmi, ""))
                    LabeledContent("% мазнини (US Navy)", value: value(navy, "%"))
                    LabeledContent("% мазнини (RFM)", value: value(rfm, "%"))
                    if let scaleFat {
                        LabeledContent("% мазнини (кантар)", value: "\(scaleFat.short) %")
                        LabeledContent("Постна маса", value: "\((kg * (1 - scaleFat / 100)).short) кг")
                    }
                }

                let bmr = BodyMath.bmr(sex: profile.sex, kg: kg, cm: profile.heightCm, age: profile.age)
                Section("Енергия") {
                    LabeledContent("BMR (Mifflin-St Jeor)", value: "\(Int(bmr)) ккал")
                    LabeledContent("Разход за деня", value: "\(Int(BodyMath.tdee(bmr: bmr, activity: profile.activityFactor))) ккал")
                }

                if let targets = BodyMath.targets(profile: profile, kg: kg) {
                    MacroEditor(profile: profile, targets: targets, kg: kg, sessions: sessions, weights: weights)
                }
            } else {
                Section {
                    Text("Попълни профила (горе вдясно в Мерки) и добави поне едно тегло.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
            } footer: {
                Text("Ориентировъчно, не е медицински съвет. Формулите имат грешка, особено % мазнини. Най-точен е трендът във времето.")
            }
        }
        .navigationTitle("Калкулатори")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Иконка за профила горе вдясно, за всеки таб.
struct ProfileToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ProfileView()
                } label: {
                    Image(systemName: "person.crop.circle")
                }
            }
        }
    }
}

extension View {
    func profileButton() -> some View { modifier(ProfileToolbarModifier()) }
}

/// Бутон "Готово" над клавиатурата: цифровите клавиатури нямат Enter.
struct KeyboardDoneModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                    to: nil, from: nil, for: nil)
                }
                .fontWeight(.semibold)
            }
        }
    }
}

extension View {
    func keyboardDoneButton() -> some View { modifier(KeyboardDoneModifier()) }
}
