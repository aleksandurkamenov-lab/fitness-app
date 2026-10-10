import SwiftUI
import SwiftData

/// Добавяне на храна към хранене: от запазените или нова.
struct AddFoodSheet: View {
    let meal: Meal
    let day: Date
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FoodItem.lastUsed, order: .reverse) private var foods: [FoodItem]
    @State private var mode = 0
    @State private var search = ""
    @State private var picked: FoodItem?
    @State private var pickedGrams = "100"
    @State private var name = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var grams = "100"
    @State private var saveToLibrary = true
    @State private var onlineQuery = ""
    @State private var onlineResults: [OnlineFood] = []
    @State private var isSearching = false
    @State private var searchMessage: String?

    private func number(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private var filtered: [FoodItem] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return foods }
        return foods.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func addEntry(name: String, grams: Double, kcal100: Double, protein100: Double, carbs100: Double, fat100: Double) {
        let factor = grams / 100
        context.insert(FoodEntry(date: day, meal: meal, name: name, grams: grams,
                                 kcal: kcal100 * factor, protein: protein100 * factor,
                                 carbs: carbs100 * factor, fat: fat100 * factor))
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Вид", selection: $mode) {
                    Text("Запазени").tag(0)
                    Text("Нова храна").tag(1)
                    Text("База").tag(2)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                if mode == 0 {
                    savedSection
                } else if mode == 1 {
                    newSection
                } else {
                    onlineSection
                }
            }
            .navigationTitle(meal.title)
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Затвори") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder private var savedSection: some View {
        Section {
            TextField("Търси", text: $search)
            if foods.isEmpty {
                Text("Още няма запазени храни. Добави първата от \"Нова храна\".")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(filtered) { food in
                Button {
                    picked = food
                    pickedGrams = food.servingG.short
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(food.name).foregroundStyle(.primary)
                            Text("на 100 г: \(food.kcalPer100.short) ккал · Б \(food.proteinPer100.short) · В \(food.carbsPer100.short) · М \(food.fatPer100.short)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if picked === food { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                    }
                }
            }
            .onDelete { offsets in
                let items = filtered
                for index in offsets {
                    if picked === items[index] { picked = nil }
                    context.delete(items[index])
                }
            }
        }
        if let picked {
            Section("Колко изяде") {
                HStack {
                    TextField("Грамове", text: $pickedGrams)
                        .keyboardType(.decimalPad)
                    Text("г").foregroundStyle(.secondary)
                }
                preview(grams: number(pickedGrams), kcal: picked.kcalPer100, protein: picked.proteinPer100,
                        carbs: picked.carbsPer100, fat: picked.fatPer100)
                Button("Добави \(picked.name)") {
                    let amount = number(pickedGrams)
                    guard amount > 0 else { return }
                    addEntry(name: picked.name, grams: amount, kcal100: picked.kcalPer100,
                             protein100: picked.proteinPer100, carbs100: picked.carbsPer100, fat100: picked.fatPer100)
                    picked.servingG = amount
                    picked.lastUsed = .now
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder private var newSection: some View {
        Section("Храна") {
            TextField("Име", text: $name)
        }
        Section {
            field("Калории", $kcal, "ккал")
            field("Белтък", $protein, "г")
            field("Въглехидрати", $carbs, "г")
            field("Мазнини", $fat, "г")
        } header: {
            Text("Стойности на 100 г")
        } footer: {
            Text("Ако знаеш общото за порцията, въведи го тук и сложи 100 г в количеството.")
        }
        Section("Колко изяде") {
            field("Количество", $grams, "г")
            Toggle("Запази в списъка", isOn: $saveToLibrary)
            preview(grams: number(grams), kcal: number(kcal), protein: number(protein),
                    carbs: number(carbs), fat: number(fat))
        }
        Section {
            Button("Добави") {
                let amount = number(grams)
                let title = name.trimmingCharacters(in: .whitespaces)
                guard amount > 0, !title.isEmpty else { return }
                let k = number(kcal), p = number(protein), c = number(carbs), f = number(fat)
                addEntry(name: title, grams: amount, kcal100: k, protein100: p, carbs100: c, fat100: f)
                if saveToLibrary {
                    let food = FoodItem(name: title, kcalPer100: k, proteinPer100: p, carbsPer100: c, fatPer100: f, servingG: amount)
                    food.lastUsed = .now
                    context.insert(food)
                }
                dismiss()
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    /// Изчислени стойности за въведеното количество.
    private func preview(grams: Double, kcal: Double, protein: Double, carbs: Double, fat: Double) -> some View {
        let factor = grams / 100
        return Text("= \((kcal * factor).short) ккал · Б \((protein * factor).short) · В \((carbs * factor).short) · М \((fat * factor).short)")
            .font(.subheadline.weight(.semibold))
    }

    @ViewBuilder private var onlineSection: some View {
        Section {
            TextField("Име на храна или продукт", text: $onlineQuery)
                .submitLabel(.search)
                .onSubmit { runSearch() }
            Button("Търси") { runSearch() }
                .disabled(onlineQuery.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
            if isSearching { ProgressView() }
            if let searchMessage {
                Text(searchMessage).font(.footnote).foregroundStyle(.secondary)
            }
        } footer: {
            Text("Данни от Open Food Facts (нужен е интернет). Избраната храна се запазва в твоя списък и после я намираш в \"Запазени\".")
        }
        Section {
            ForEach(onlineResults) { food in
                Button {
                    let item = FoodItem(name: food.name, kcalPer100: food.kcal, proteinPer100: food.protein,
                                        carbsPer100: food.carbs, fatPer100: food.fat)
                    item.lastUsed = .now
                    context.insert(item)
                    picked = item
                    pickedGrams = "100"
                    mode = 0
                } label: {
                    VStack(alignment: .leading) {
                        Text(food.name).foregroundStyle(.primary)
                        Text("на 100 г: \(food.kcal.short) ккал · Б \(food.protein.short) · В \(food.carbs.short) · М \(food.fat.short)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func runSearch() {
        let query = onlineQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, !isSearching else { return }
        isSearching = true
        searchMessage = nil
        Task {
            do {
                let results = try await FoodSearch.search(query)
                onlineResults = results
                searchMessage = results.isEmpty ? "Няма резултати." : nil
            } catch {
                onlineResults = []
                searchMessage = "Не успях да търся: \(error.localizedDescription)"
            }
            isSearching = false
        }
    }

    private func field(_ title: String, _ text: Binding<String>, _ unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}
