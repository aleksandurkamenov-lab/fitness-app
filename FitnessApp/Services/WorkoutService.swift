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
            for index in 0..<max(item.targetSets, 1) {
                let old = index < previous.count ? previous[index] : nil
                let set = SetEntry(
                    exercise: exercise,
                    exerciseOrder: item.order,
                    setIndex: index,
                    weight: old?.weight ?? 0,
                    reps: old?.reps ?? 0,
                    targetRepMin: item.repMin,
                    targetRepMax: item.repMax,
                    restSeconds: item.restSeconds
                )
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
                $0.isDone && $0.exercise?.persistentModelID == exercise.persistentModelID
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
                $0.isDone && $0.exercise?.persistentModelID == exercise.persistentModelID
            }
            return sets.isEmpty ? nil : ExerciseHistoryEntry(session: session, sets: sets)
        }
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
