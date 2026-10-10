import Foundation
import SwiftData

/// Логика около тренировките, която не е свързана с конкретен екран.
enum WorkoutService {
    /// Започва тренировка по шаблон. При `copyPrevious` попълва кг и повторения от последния път.
    static func startSession(from template: WorkoutTemplate, copyPrevious: Bool, in context: ModelContext) -> WorkoutSession {
        let week = template.mesocycle?.currentWeek ?? 1
        let session = WorkoutSession(week: week, template: template)
        context.insert(session)

        for item in template.sortedItems {
            guard let exercise = item.exercise else { continue }
            let previous = copyPrevious ? lastSets(for: exercise, before: session.date, in: context) : []
            let targets = item.targets
            for (index, target) in targets.enumerated() {
                let old = index < previous.count ? previous[index] : nil
                let set = SetEntry(
                    exercise: exercise,
                    exerciseOrder: item.order,
                    setIndex: index,
                    weight: old?.weight ?? 0,
                    reps: old?.reps ?? 0,
                    targetRepMin: target.repMin,
                    targetRepMax: target.repMax,
                    restSeconds: item.restSeconds,
                    bestWeight: target.bestWeight ?? 0,
                    bestReps: target.bestReps ?? 0,
                    exerciseNote: index == 0 ? item.note : "",
                    plannedWeight: target.plannedWeight ?? 0
                )
                set.supersetNext = item.supersetNext
                set.session = session
                context.insert(set)
            }
        }
        return session
    }

    /// Сериите за упражнението от последната завършена тренировка преди дадена дата.
    static func lastSets(for exercise: Exercise, before date: Date, in context: ModelContext) -> [SetEntry] {
        let descriptor = FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let sessions = (try? context.fetch(descriptor)) ?? []
        for session in sessions where session.isFinished && session.date < date {
            let sets = session.sortedSets.filter {
                $0.isWorkSet && $0.exercise?.persistentModelID == exercise.persistentModelID
            }
            if !sets.isEmpty { return sets }
        }
        return []
    }

    /// Всички завършени серии на упражнение, групирани по тренировка (най-новите първи).
    static func history(for exercise: Exercise, in context: ModelContext) -> [ExerciseHistoryEntry] {
        let descriptor = FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let sessions = (try? context.fetch(descriptor)) ?? []
        return sessions.compactMap { session in
            guard session.isFinished else { return nil }
            let sets = session.sortedSets.filter {
                $0.isWorkSet && $0.exercise?.persistentModelID == exercise.persistentModelID
            }
            return sets.isEmpty ? nil : ExerciseHistoryEntry(session: session, sets: sets)
        }
    }

    /// Най-добрата тежест и 1RM за упражнението от тренировки преди дадена дата.
    static func records(for exercise: Exercise, before date: Date, in context: ModelContext) -> (weight: Double, oneRM: Double) {
        let sets = history(for: exercise, in: context)
            .filter { $0.session.date < date }
            .flatMap(\.sets)
            .filter { $0.reps > 0 }
        return (sets.map(\.weight).max() ?? 0, sets.map(\.estimatedOneRepMax).max() ?? 0)
    }

    /// Загряващи серии 40/60/80 % преди работните. Старите загрявки се махат.
    static func addWarmups(to group: ExerciseGroup, baseWeight: Double, session: WorkoutSession, in context: ModelContext) {
        for set in group.sets where set.isWarmup { context.delete(set) }
        let steps: [(percent: Double, reps: Int)] = [(0.4, 8), (0.6, 5), (0.8, 3)]
        for (index, step) in steps.enumerated() {
            let set = SetEntry(exercise: group.exercise, exerciseOrder: group.order, setIndex: index - steps.count,
                               weight: WorkoutMath.warmupWeight(baseWeight, percent: step.percent), reps: step.reps,
                               restSeconds: 60)
            set.isWarmup = true
            set.supersetNext = group.isSuperset
            set.session = session
            context.insert(set)
        }
    }

    /// Следващ мезоцикъл от предишния: същите тренировки и упражнения.
    /// Най-добрите резултати от стария стават "най-добро до сега", а последните килограми се попълват като планирани.
    @discardableResult
    static func continueMesocycle(_ old: Mesocycle, in context: ModelContext) -> Mesocycle {
        let meso = Mesocycle(name: nextName(after: old.name), weekCount: old.weekCount)
        context.insert(meso)
        let oldTemplates = Set(old.templates.map(\.persistentModelID))
        let allSessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let oldSessions = allSessions.filter { session in
            guard session.isFinished, let id = session.template?.persistentModelID else { return false }
            return oldTemplates.contains(id)
        }

        for oldTemplate in old.sortedTemplates {
            let template = WorkoutTemplate(name: oldTemplate.name, order: oldTemplate.order)
            template.mesocycle = meso
            context.insert(template)

            for oldItem in oldTemplate.sortedItems {
                guard let exercise = oldItem.exercise else { continue }
                let item = TemplateExercise(exercise: exercise, order: oldItem.order, targetSets: oldItem.targetSets,
                                            repMin: oldItem.repMin, repMax: oldItem.repMax,
                                            restSeconds: oldItem.restSeconds, note: oldItem.note)
                item.supersetNext = oldItem.supersetNext
                item.template = template
                context.insert(item)

                let done = oldSessions.flatMap(\.sets).filter {
                    $0.isWorkSet && $0.exercise?.persistentModelID == exercise.persistentModelID
                }
                let last = lastSets(for: exercise, before: .now, in: context)
                item.targets = oldItem.targets.enumerated().map { index, target in
                    var next = target
                    let sameSet = done.filter { $0.setIndex == index }
                    let pool = sameSet.isEmpty ? done : sameSet
                    if let best = pool.max(by: { $0.estimatedOneRepMax < $1.estimatedOneRepMax }) {
                        next.bestWeight = best.weight
                        next.bestReps = Double(best.reps)
                    }
                    if index < last.count, last[index].weight > 0 {
                        next.plannedWeight = last[index].weight
                    }
                    return next
                }
            }
        }
        return meso
    }

    /// "Meso 22" -> "Meso 23"; без число накрая -> "… 2".
    private static func nextName(after name: String) -> String {
        let digits = String(name.reversed().prefix { $0.isNumber }.reversed())
        guard let number = Int(digits), !digits.isEmpty else { return name + " 2" }
        return String(name.dropLast(digits.count)) + String(number + 1)
    }

    /// Нов мезоцикъл с 4 празни тренировки Upper/Lower/Upper/Lower.
    @discardableResult
    static func createMesocycle(name: String, weeks: Int, in context: ModelContext) -> Mesocycle {
        let meso = Mesocycle(name: name, weekCount: weeks)
        context.insert(meso)
        for (index, title) in ["Upper 1", "Lower 1", "Upper 2", "Lower 2"].enumerated() {
            let template = WorkoutTemplate(name: title, order: index)
            template.mesocycle = meso
            context.insert(template)
        }
        return meso
    }
}

struct ExerciseHistoryEntry: Identifiable {
    let session: WorkoutSession
    let sets: [SetEntry]
    var id: PersistentIdentifier { session.persistentModelID }
}
