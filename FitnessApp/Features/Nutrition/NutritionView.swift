import SwiftUI
import SwiftData

struct NutritionView: View {
    @Query(sort: \FoodEntry.date) private var entries: [FoodEntry]
    @Query private var profiles: [UserProfile]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Environment(\.modelContext) private var context
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var addingMeal: Meal?
    @State private var editing: FoodEntry?
    @State private var health = HealthService()
    @State private var healthDays: [Date: NutritionDay] = [:]

    private var calendar: Calendar { Calendar.current }

    private func entries(on date: Date) -> [FoodEntry] {
        entries.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// Дневни цели: от профила и последното тегло; ръчно зададените макроси имат предимство.
    private var targets: BodyMath.Targets? {
        guard let profile = profiles.first, let kg = weights.last?.kg,
              let base = BodyMath.targets(profile: profile, kg: kg) else { return nil }
        var result = base
        let custom = profile.customProteinG > 0 || profile.customFatG > 0 || profile.customCarbsG > 0
        if profile.customProteinG > 0 { result.protein = profile.customProteinG }
        if profile.customFatG > 0 { result.fat = profile.customFatG }
        if profile.customCarbsG > 0 { result.carbs = profile.customCarbsG }
        if custom { result.kcal = result.protein * 4 + result.carbs * 4 + result.fat * 9 }
        return result
    }

    private var dayTitle: String {
        if calendar.isDateInToday(day) { return "Днес" }
        if calendar.isDateInYesterday(day) { return "Вчера" }
        return day.formatted(.dateTime.weekday(.wide).day().month())
    }

    private func shiftDay(_ value: Int) {
        day = calendar.date(byAdding: .day, value: value, to: day) ?? day
    }

    private func copyPreviousDay() {
        let previous = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        for entry in entries(on: previous) {
            context.insert(FoodEntry(date: day, meal: entry.meal, name: entry.name, grams: entry.grams,
                                     kcal: entry.kcal, protein: entry.protein, carbs: entry.carbs, fat: entry.fat))
        }
    }

    var body: some View {
        let today = entries(on: day)
        let fromHealth = healthDays[calendar.startOfDay(for: day)] ?? NutritionDay()
        NavigationStack {
            List {
                Section {
                    HStack {
                        Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
                            .buttonStyle(.borderless)
                        Spacer()
                        Text(dayTitle).font(.headline)
                        Spacer()
                        Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }
                            .buttonStyle(.borderless)
                            .disabled(calendar.isDateInToday(day))
                    }
                }

                Section("Общо за деня") {
                    MacroBar(title: "Калории", value: today.reduce(0) { $0 + $1.kcal } + fromHealth.kcal, target: targets?.kcal, unit: "ккал")
                    MacroBar(title: "Белтък", value: today.reduce(0) { $0 + $1.protein } + fromHealth.protein, target: targets?.protein, unit: "г")
                    MacroBar(title: "Въглехидрати", value: today.reduce(0) { $0 + $1.carbs } + fromHealth.carbs, target: targets?.carbs, unit: "г")
                    MacroBar(title: "Мазнини", value: today.reduce(0) { $0 + $1.fat } + fromHealth.fat, target: targets?.fat, unit: "г")
                    if fromHealth.kcal > 0 {
                        Text("Вкл. от Apple Health (напр. MyFitnessPal): \(fromHealth.kcal.short) ккал")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if targets == nil {
                        Text("За цели попълни профила и теглото си (икона горе в дясно, Мерки).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(Meal.allCases) { meal in
                    let items = today.filter { $0.meal == meal }
                    Section {
                        ForEach(items) { entry in
                            Button {
                                editing = entry
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(entry.name).foregroundStyle(.primary)
                                        Spacer()
                                        Text("\(entry.kcal.short) ккал").foregroundStyle(.secondary)
                                    }
                                    Text("\(entry.grams.short) г · Б \(entry.protein.short) · В \(entry.carbs.short) · М \(entry.fat.short)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(items[index]) }
                        }
                        Button {
                            addingMeal = meal
                        } label: {
                            Label("Добави", systemImage: "plus")
                        }
                    } header: {
                        HStack {
                            Text(meal.title)
                            Spacer()
                            if !items.isEmpty {
                                Text("\(items.reduce(0) { $0 + $1.kcal }.short) ккал")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Хранене")
            .profileButton()
            .task { healthDays = await health.nutrition(days: 14) }
            .refreshable { healthDays = await health.nutrition(days: 14) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Копирай вчера", systemImage: "doc.on.doc") { copyPreviousDay() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(item: $addingMeal) { meal in
                AddFoodSheet(meal: meal, day: day)
            }
            .sheet(item: $editing) { entry in
                EditEntrySheet(entry: entry)
            }
        }
    }
}

private struct MacroBar: View {
    let title: String
    let value: Double
    let target: Double?
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                if let target {
                    Text("\(value.short) / \(target.short) \(unit)")
                        .foregroundStyle(value > target ? Color.orange : Color.secondary)
                } else {
                    Text("\(value.short) \(unit)").foregroundStyle(.secondary)
                }
            }
            if let target, target > 0 {
                ProgressView(value: min(value / target, 1))
                    .tint(value > target ? Color.orange : Color.accentColor)
            }
        }
    }
}


/// Промяна на количеството: калориите и макросите се преизчисляват автоматично.
private struct EditEntrySheet: View {
    let entry: FoodEntry
    @Environment(\.dismiss) private var dismiss
    @State private var gramsText = ""

    private var grams: Double {
        Double(gramsText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private var factor: Double { entry.grams > 0 ? grams / entry.grams : 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section(entry.name) {
                    HStack {
                        Text("Количество")
                        Spacer()
                        TextField("0", text: $gramsText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                        Text("г").foregroundStyle(.secondary)
                    }
                    Text("= \((entry.kcal * factor).short) ккал · Б \((entry.protein * factor).short) · В \((entry.carbs * factor).short) · М \((entry.fat * factor).short)")
                        .font(.subheadline.weight(.semibold))
                }
                Section {
                    Button("Запази") {
                        guard grams > 0, entry.grams > 0 else { return }
                        let scale = grams / entry.grams
                        entry.kcal *= scale
                        entry.protein *= scale
                        entry.carbs *= scale
                        entry.fat *= scale
                        entry.grams = grams
                        dismiss()
                    }
                    .disabled(grams <= 0)
                }
            }
            .navigationTitle("Количество")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Затвори") { dismiss() }
                }
            }
            .onAppear { gramsText = entry.grams.short }
        }
    }
}
