import Foundation
import SwiftData

/// Импорт на мезоцикъл от JSON, получен от треньорския Excel (виж tools/xlsx_to_json.py).
enum MesoImporter {
    struct Payload: Decodable {
        struct Workout: Decodable {
            struct Item: Decodable {
                var name: String
                var muscle: String
                var note: String
                var sets: [SetTarget]
            }
            var name: String
            var exercises: [Item]
        }
        var name: String
        var weeks: Int
        var workouts: [Workout]
    }

    enum ImportError: LocalizedError {
        case missingFile
        case alreadyImported(String)

        var errorDescription: String? {
            switch self {
            case .missingFile: "Не намирам файла с мезоцикъла в приложението."
            case .alreadyImported(let name): "„\(name)“ вече е импортиран."
            }
        }
    }

    /// Импортира мезоцикъла, който е вграден в приложението (Meso22.json).
    @discardableResult
    static func importBundledMeso(in context: ModelContext) throws -> Mesocycle {
        guard let url = Bundle.main.url(forResource: "Meso22", withExtension: "json")
                ?? Bundle.main.url(forResource: "Meso22", withExtension: "json", subdirectory: "Resources") else {
            throw ImportError.missingFile
        }
        let payload = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: url))
        return try importPayload(payload, in: context)
    }

    @discardableResult
    static func importPayload(_ payload: Payload, in context: ModelContext) throws -> Mesocycle {
        let existing = (try? context.fetch(FetchDescriptor<Mesocycle>())) ?? []
        if existing.contains(where: { $0.name == payload.name }) {
            throw ImportError.alreadyImported(payload.name)
        }

        var library = Dictionary(
            ((try? context.fetch(FetchDescriptor<Exercise>())) ?? []).map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let meso = Mesocycle(name: payload.name, weekCount: payload.weeks)
        context.insert(meso)

        for (workoutIndex, workout) in payload.workouts.enumerated() {
            let template = WorkoutTemplate(name: workout.name, order: workoutIndex)
            template.mesocycle = meso
            context.insert(template)

            for (itemIndex, item) in workout.exercises.enumerated() {
                let key = item.name.lowercased()
                let exercise: Exercise
                if let found = library[key] {
                    exercise = found
                } else {
                    exercise = Exercise(
                        name: item.name,
                        primary: MuscleGroup(rawValue: item.muscle) ?? .chest,
                        isCustom: true
                    )
                    context.insert(exercise)
                    library[key] = exercise
                }

                let entry = TemplateExercise(exercise: exercise, order: itemIndex, note: item.note)
                entry.template = template
                context.insert(entry)
                entry.targets = item.sets.isEmpty ? [SetTarget(repMin: 8, repMax: 12)] : item.sets
            }
        }
        try context.save()
        return meso
    }
}
