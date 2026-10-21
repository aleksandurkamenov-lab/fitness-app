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
        case noWorkouts

        var errorDescription: String? {
            switch self {
            case .missingFile: "Не намирам файла с мезоцикъла в приложението."
            case .alreadyImported(let name): "„\(name)“ вече е импортиран."
            case .noWorkouts: "В този лист не намерих тренировки (очаквам форматa на треньорския Excel)."
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

    // MARK: Excel (.xlsx) на треньора

    private static let commentLabel = "Коментар по упражнението"
    private static let skipComments: Set<String> = ["Link", "Най - добри резултати до сега -->"]
    private static let muscleKeywords: [(String, [String])] = [
        ("calves", ["calves", "calf"]),
        ("glutes", ["hip thrust", "glute"]),
        ("hamstrings", ["rdl", "leg curl", "hamstring", "deadlift"]),
        ("quads", ["leg press", "squat", "leg extension", "lunge", "adductor"]),
        ("abs", ["crunch", "abs", "leg raise"]),
        ("biceps", ["curl", "biceps"]),
        ("triceps", ["tricep", "pushdown", "extension", "skull"]),
        ("shoulders", ["lateral", "overhead", "shoulder", "reverce", "reverse pec", "face pull", "rear delt"]),
        ("back", ["pulldown", "row", "pull-up", "pullup", "shrug", "lat "]),
        ("chest", ["bench", "chest", "pec", "fly", "push"]),
    ]

    /// Листовете, които приличат на мезоцикъл („Месо 22“, „Meso 5“, „Меso 30 Upper Lower“...).
    static func mesoSheetNames(in workbook: XlsxWorkbook) -> [String] {
        let lookalike: [Character: Character] = ["м": "m", "е": "e", "с": "c", "о": "o"]
        return workbook.sheetNames.filter { name in
            let folded = String(name.lowercased().map { lookalike[$0] ?? $0 })
            return folded.contains("meso") || folded.contains("meco")
        }
    }

    /// Чете един лист на треньорския Excel (тренировки на ред 6, упражнения на блокове по 7 реда).
    static func payload(from sheet: XlsxWorkbook.Sheet, name: String) -> Payload {
        var workouts: [Payload.Workout] = []
        let starts = (1...max(sheet.maxCol, 1)).filter {
            !(sheet.text(6, $0)?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        }
        for start in starts {
            var items: [Payload.Workout.Item] = []
            for row in 7...max(sheet.maxRow, 7) {
                guard let title = sheet.text(row, start)?.trimmingCharacters(in: .whitespaces), !title.isEmpty,
                      sheet.text(row, start + 3) == commentLabel else { continue }

                var sets: [SetTarget] = []
                var offset = 5
                while offset + 2 < sheet.maxCol - start + 1,
                      let range = parseRange(sheet.text(row + 3, start + offset)) {
                    var target = SetTarget(repMin: range.0, repMax: range.1)
                    target.bestWeight = sheet.number(row + 2, start + offset + 1)
                    target.bestReps = sheet.number(row + 2, start + offset + 2)
                    sets.append(target)
                    offset += 3
                }

                let notes = (row + 1...row + 6).compactMap { sheet.text($0, start + 3)?.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && !skipComments.contains($0) }
                items.append(.init(name: title, muscle: guessMuscle(title), note: notes.joined(separator: " · "), sets: sets))
            }
            let workoutName = sheet.text(6, start)?.trimmingCharacters(in: .whitespaces) ?? "Тренировка"
            workouts.append(.init(name: workoutName, exercises: items))
        }
        let cleaned = name.split(separator: " ").joined(separator: " ")
        return Payload(name: cleaned, weeks: 4, workouts: workouts)
    }

    private static func parseRange(_ value: String?) -> (Int, Int)? {
        guard let value else { return nil }
        let parts = value.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let low = Int(parts[0]), let high = Int(parts[1]) else { return nil }
        return (low, high)
    }

    private static func guessMuscle(_ name: String) -> String {
        let lowered = name.lowercased()
        for (muscle, words) in muscleKeywords where words.contains(where: { lowered.contains($0) }) {
            return muscle
        }
        return "chest"
    }

    @discardableResult
    static func importSheet(named sheetName: String, from workbook: XlsxWorkbook, in context: ModelContext) throws -> Mesocycle {
        let sheet = try workbook.sheet(named: sheetName)
        let payload = payload(from: sheet, name: sheetName)
        guard payload.workouts.contains(where: { !$0.exercises.isEmpty }) else { throw ImportError.noWorkouts }
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
