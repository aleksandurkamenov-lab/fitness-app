import SwiftUI
import SwiftData

struct NutritionView: View {
    @Query(sort: \FoodEntry.date) private var entries: [FoodEntry]
    @Query private var profiles: [UserProfile]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Environment(\.modelContext) private var context
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var addingMeal: Meal?

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
                    MacroBar(title: "Калории", value: today.reduce(0) { $0 + $1.kcal }, target: targets?.kcal, unit: "ккал")
                    MacroBar(title: "Белтък", value: today.reduce(0) { $0 + $1.protein }, target: targets?.protein, unit: "г")
                    MacroBar(title: "Въглехидрати", value: today.reduce(0) { $0 + $1.carbs }, target: targets?.carbs, unit: "г")
                    MacroBar(title: "Мазнини", value: today.reduce(0) { $0 + $1.fat }, target: targets?.fat, unit: "г")
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
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(entry.name)
                                    Spacer()
                                    Text("\(entry.kcal.short) ккал").foregroundStyle(.secondary)
                                }
                                Text("\(entry.grams.short) г · Б \(entry.protein.short) · В \(entry.carbs.short) · М \(entry.fat.short)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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

