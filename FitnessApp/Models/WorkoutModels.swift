import Foundation
import SwiftData

@Model
final class Exercise {
    var name: String
    var primaryMuscleRaw: String
    var secondaryMusclesRaw: [String]
    var notes: String
    var isCustom: Bool

    init(name: String, primary: MuscleGroup, secondary: [MuscleGroup] = [], notes: String = "", isCustom: Bool = false) {
        self.name = name
        self.primaryMuscleRaw = primary.rawValue
        self.secondaryMusclesRaw = secondary.map(\.rawValue)
        self.notes = notes
        self.isCustom = isCustom
    }

    var primaryMuscle: MuscleGroup {
        get { MuscleGroup(rawValue: primaryMuscleRaw) ?? .chest }
        set { primaryMuscleRaw = newValue.rawValue }
    }

    var secondaryMuscles: [MuscleGroup] {
        secondaryMusclesRaw.compactMap(MuscleGroup.init(rawValue:))
    }
}

/// Мезоцикъл: няколко седмици с еднакъв набор тренировки (напр. Upper/Lower/Upper/Lower).
@Model
final class Mesocycle {
    var name: String
    var startDate: Date
    var weekCount: Int
    @Relationship(deleteRule: .cascade, inverse: \WorkoutTemplate.mesocycle)
    var templates: [WorkoutTemplate] = []

    init(name: String, startDate: Date = .now, weekCount: Int = 4) {
        self.name = name
        self.startDate = startDate
        self.weekCount = weekCount
    }

    var sortedTemplates: [WorkoutTemplate] {
        templates.sorted { $0.order < $1.order }
    }

    /// Текущата седмица спрямо началото, в границите 1...weekCount.
    var currentWeek: Int {
        let days = Calendar.current.dateComponents([.day], from: startDate, to: .now).day ?? 0
        return min(max(days / 7 + 1, 1), weekCount)
    }
}

/// Шаблон на тренировка, напр. „Upper 1“.
@Model
final class WorkoutTemplate {
    var name: String
    var order: Int
    var mesocycle: Mesocycle?
    @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.template)
    var items: [TemplateExercise] = []

    init(name: String, order: Int) {
        self.name = name
        self.order = order
    }

    var sortedItems: [TemplateExercise] {
        items.sorted { $0.order < $1.order }
    }
}

/// Цел за една серия: диапазон повторения и (по избор) най-добър резултат до момента.
struct SetTarget: Codable, Hashable {
    var repMin: Int
    var repMax: Int
    var bestWeight: Double?
    var bestReps: Double?
    /// Работна тежест, която потребителят е планирал за серията (по избор).
    var plannedWeight: Double?

    var rangeText: String {
        repMin == repMax ? "\(repMin)" : "\(repMin)–\(repMax)"
    }

    var bestText: String? {
        guard let bestWeight, let bestReps else { return nil }
        return "\(bestWeight.short)×\(bestReps.short)"
    }
}

/// Упражнение в шаблон с целеви серии и диапазон повторения за всяка серия.
@Model
final class TemplateExercise {
    var order: Int
    var targetSets: Int
    var repMin: Int
    var repMax: Int
    var restSeconds: Int
    var note: String
    var setTargets: [SetTarget] = []
    /// Суперсерия: това упражнение се прави заедно със следващото.
    var supersetNext: Bool = false
    var exercise: Exercise?
    var template: WorkoutTemplate?

    init(exercise: Exercise, order: Int, targetSets: Int = 3, repMin: Int = 8, repMax: Int = 12, restSeconds: Int = 120, note: String = "") {
        self.exercise = exercise
        self.order = order
        self.targetSets = targetSets
        self.repMin = repMin
        self.repMax = repMax
        self.restSeconds = restSeconds
        self.note = note
    }

    /// Целите по серии. Ако няма отделни цели, всички серии са с един и същ диапазон.
    var targets: [SetTarget] {
        get {
            if !setTargets.isEmpty { return setTargets }
            return Array(repeating: SetTarget(repMin: repMin, repMax: repMax), count: max(targetSets, 1))
        }
        set {
            setTargets = newValue
            targetSets = newValue.count
            if let first = newValue.first {
                repMin = first.repMin
                repMax = first.repMax
            }
        }
    }

    var targetText: String {
        targets.map(\.rangeText).joined(separator: " · ")
    }
}

/// Една проведена (или текуща) тренировка.
@Model
final class WorkoutSession {
    var date: Date
    var finishedAt: Date?
    var week: Int
    var notes: String
    var template: WorkoutTemplate?
    @Relationship(deleteRule: .cascade, inverse: \SetEntry.session)
    var sets: [SetEntry] = []

    init(date: Date = .now, week: Int = 1, template: WorkoutTemplate? = nil) {
        self.date = date
        self.week = week
        self.template = template
        self.notes = ""
    }

    var title: String {
        template?.name ?? "Тренировка"
    }

    var isFinished: Bool { finishedAt != nil }

    var sortedSets: [SetEntry] {
        sets.sorted { ($0.exerciseOrder, $0.setIndex) < ($1.exerciseOrder, $1.setIndex) }
    }

    /// Сериите, групирани по упражнение, в реда на тренировката.
    var exerciseGroups: [ExerciseGroup] {
        var groups: [ExerciseGroup] = []
        for set in sortedSets {
            if let last = groups.last, last.order == set.exerciseOrder {
                groups[groups.count - 1].sets.append(set)
            } else {
                groups.append(ExerciseGroup(order: set.exerciseOrder, exercise: set.exercise, sets: [set]))
            }
        }
        return groups
    }
}

struct ExerciseGroup: Identifiable {
    let order: Int
    let exercise: Exercise?
    var sets: [SetEntry]
    var id: Int { order }

    /// Свързано в суперсерия със следващото упражнение.
    var isSuperset: Bool { sets.contains { $0.supersetNext } }
    var firstWorkSet: SetEntry? { sets.first { !$0.isWarmup } ?? sets.first }
}

@Model
final class SetEntry {
    var exerciseOrder: Int
    var setIndex: Int
    var weight: Double
    var reps: Int
    var isDone: Bool
    var targetRepMin: Int
    var targetRepMax: Int
    var restSeconds: Int
    var bestWeight: Double = 0
    var bestReps: Double = 0
    var exerciseNote: String = ""
    /// Планирана тежест от шаблона; показва се като напомняне, докато не въведеш реална.
    var plannedWeight: Double = 0
    /// Загряваща серия: не влиза в обема, рекордите и „последния път“.
    var isWarmup: Bool = false
    /// Повторения в резерв (RIR), -1 = не е въведено.
    var rir: Int = -1
    /// Суперсерия със следващото упражнение.
    var supersetNext: Bool = false
    var exercise: Exercise?
    var session: WorkoutSession?

    init(exercise: Exercise?, exerciseOrder: Int, setIndex: Int, weight: Double = 0, reps: Int = 0,
         targetRepMin: Int = 0, targetRepMax: Int = 0, restSeconds: Int = 120,
         bestWeight: Double = 0, bestReps: Double = 0, exerciseNote: String = "", plannedWeight: Double = 0) {
        self.exercise = exercise
        self.exerciseOrder = exerciseOrder
        self.setIndex = setIndex
        self.weight = weight
        self.reps = reps
        self.isDone = false
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.restSeconds = restSeconds
        self.bestWeight = bestWeight
        self.bestReps = bestReps
        self.exerciseNote = exerciseNote
        self.plannedWeight = plannedWeight
    }

    var volume: Double { weight * Double(reps) }
    /// Завършена работна серия (без загрявките).
    var isWorkSet: Bool { isDone && !isWarmup }
    var estimatedOneRepMax: Double { WorkoutMath.epley(weight: weight, reps: reps) }
}
