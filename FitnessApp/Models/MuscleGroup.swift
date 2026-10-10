import Foundation

/// Мускулни групи за седмичния обем и библиотеката с упражнения.
enum MuscleGroup: String, Codable, CaseIterable, Identifiable {
    case chest, back, shoulders, biceps, triceps, forearms, quads, hamstrings, glutes, calves, abs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chest: "Гърди"
        case .back: "Гръб"
        case .shoulders: "Рамене"
        case .biceps: "Бицепс"
        case .triceps: "Трицепс"
        case .forearms: "Предмишници"
        case .quads: "Квадрицепс"
        case .hamstrings: "Задно бедро"
        case .glutes: "Седалище"
        case .calves: "Прасци"
        case .abs: "Корем"
        }
    }
}
