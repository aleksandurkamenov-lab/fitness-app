import Foundation
import SwiftData

enum Meal: String, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: "Закуска"
        case .lunch: "Обяд"
        case .dinner: "Вечеря"
        case .snack: "Закуски между храненията"
        }
    }
}

/// Запазена храна с хранителни стойности на 100 г.
@Model
final class FoodItem {
    var name: String = ""
    var kcalPer100: Double = 0
    var proteinPer100: Double = 0
    var carbsPer100: Double = 0
    var fatPer100: Double = 0
    var servingG: Double = 100
    var lastUsed: Date = Date.distantPast

    init(name: String, kcalPer100: Double, proteinPer100: Double, carbsPer100: Double, fatPer100: Double, servingG: Double = 100) {
        self.name = name
        self.kcalPer100 = kcalPer100
        self.proteinPer100 = proteinPer100
        self.carbsPer100 = carbsPer100
        self.fatPer100 = fatPer100
        self.servingG = servingG
    }
}

/// Записано ядене: общите стойности за изядените грамове.
@Model
final class FoodEntry {
    var date: Date = Date.now
    var mealRaw: String = Meal.breakfast.rawValue
    var name: String = ""
    var grams: Double = 100
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0

    var meal: Meal { Meal(rawValue: mealRaw) ?? .snack }

    init(date: Date, meal: Meal, name: String, grams: Double, kcal: Double, protein: Double, carbs: Double, fat: Double) {
        self.date = date
        self.mealRaw = meal.rawValue
        self.name = name
        self.grams = grams
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }
}
