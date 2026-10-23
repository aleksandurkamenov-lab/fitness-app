import Foundation
import SwiftData

/// Експорт на данните в един JSON файл и внос на тренировки от Strong/Hevy (CSV).
enum DataTransfer {
    struct Backup: Codable {
        struct Weight: Codable { var date: Date; var kg: Double; var bodyFat: Double? }
        struct Measurement: Codable { var date: Date; var kind: String; var cm: Double }
        struct Workout: Codable {
            struct SetItem: Codable {
                var exercise: String; var order: Int; var index: Int
                var weight: Double; var reps: Double; var warmup: Bool; var rir: Int
            }
            var date: Date; var finishedAt: Date?; var title: String; var sets: [SetItem]
        }
        var exportedAt: Date
        var weights: [Weight]
        var measurements: [Measurement]
        var workouts: [Workout]
    }

    /// Записва всичко във временен файл и връща адреса му за споделяне.
    static func exportJSON(in context: ModelContext) throws -> URL {
        let weights = try context.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date)]))
        let measurements = try context.fetch(FetchDescriptor<MeasurementEntry>(sortBy: [SortDescriptor(\.date)]))
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date)]))
        let backup = Backup(
            exportedAt: .now,
            weights: weights.map { .init(date: $0.date, kg: $0.kg, bodyFat: $0.bodyFatPercent) },
            measurements: measurements.map { .init(date: $0.date, kind: $0.kindRaw, cm: $0.cm) },
            workouts: sessions.map { session in
                .init(date: session.date, finishedAt: session.finishedAt, title: session.title,
                      sets: session.sortedSets.map {
                          .init(exercise: $0.exercise?.name ?? "", order: $0.exerciseOrder, index: $0.setIndex,
                                weight: $0.weight, reps: $0.repsValue, warmup: $0.isWarmup, rir: $0.rir)
                      })
            })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fitness-backup.json")
        try encoder.encode(backup).write(to: url, options: .atomic)
        return url
    }

    /// Еднократно добавя DEXA сканирането на потребителя от юли 2025 г. (94 кг, 18 % мазнини, 74 кг постна маса).
    static func seedUserDexaIfNeeded(in context: ModelContext) {
        let key = "seedDexa2025"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        var components = DateComponents()
        components.year = 2025; components.month = 7; components.day = 15
        let date = Calendar.current.date(from: components) ?? .now
        context.insert(BodyScan(date: date, weightKg: 94, bodyFatPercent: 18, leanMassKg: 74, kind: "DEXA"))
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }

    // MARK: - CSV (Strong, Hevy)

    /// Разбира CSV с кавички; връща редове от полета.
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var iterator = text.makeIterator()
        var pending: Character? = nil
        while let char = pending ?? iterator.next() {
            pending = nil
            if quoted {
                if char == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { quoted = false; pending = next }
                    } else { quoted = false }
                } else { field.append(char) }
            } else if char == "\"" {
                quoted = true
            } else if char == "," || char == ";" {
                row.append(field); field = ""
            } else if char == "\n" || char == "\r\n" {
                row.append(field); field = ""
                if !row.allSatisfy(\.isEmpty) { rows.append(row) }
                row = []
            } else if char != "\r" {
                field.append(char)
            }
        }
        row.append(field)
        if !row.allSatisfy(\.isEmpty) { rows.append(row) }
        return rows
    }

    private static let dateFormats = ["yyyy-MM-dd HH:mm:ss", "d MMM yyyy, HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"]

    private static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in dateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text.trimmingCharacters(in: .whitespaces)) { return date }
        }
        return nil
    }

    private static func guessMuscle(_ name: String) -> MuscleGroup {
        let n = name.lowercased()
        let rules: [(MuscleGroup, [String])] = [
            (.triceps, ["tricep", "pushdown", "skull", "dip"]),
            (.biceps, ["curl"]),
            (.hamstrings, ["hamstring", "leg curl", "romanian", "stiff"]),
            (.glutes, ["hip thrust", "glute", "kickback"]),
            (.quads, ["squat", "leg press", "leg extension", "lunge", "hack"]),
            (.calves, ["calf"]),
            (.abs, ["crunch", "plank", "sit up", "sit-up", "ab ", "leg raise"]),
            (.forearms, ["wrist", "forearm"]),
            (.shoulders, ["shoulder", "overhead", "lateral", "military", "face pull", "rear delt"]),
            (.chest, ["bench", "chest", "fly", "push up", "push-up", "pec"]),
            (.back, ["row", "pull", "lat ", "deadlift", "chin", "shrug"])
        ]
        return rules.first { rule in rule.1.contains { n.contains($0) } }?.0 ?? .back
    }

    /// Внася тренировки от CSV на Strong или Hevy (килограми). Връща брой нови тренировки.
    static func importCSV(_ text: String, in context: ModelContext) throws -> Int {
        let rows = parseCSV(text)
        guard let header = rows.first else { return 0 }
        let names = header.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func col(_ keys: [String]) -> Int? { names.firstIndex { keys.contains($0) } }
        guard let dateCol = col(["date", "start_time"]),
              let exerciseCol = col(["exercise name", "exercise_title"]) else {
            throw ImportError.unknownFormat
        }
        let titleCol = col(["workout name", "title"])
        let endCol = col(["end_time"])
        let weightCol = col(["weight", "weight_kg"])
        let repsCol = col(["reps"])
        let typeCol = col(["set_type"])
        let rpeCol = col(["rpe"])

        var exercises = Dictionary(
            try context.fetch(FetchDescriptor<Exercise>()).map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first })
        let existing = try context.fetch(FetchDescriptor<WorkoutSession>()).map(\.date)

        func cell(_ row: [String], _ index: Int?) -> String {
            guard let index, index < row.count else { return "" }
            return row[index]
        }

        var sessions: [String: WorkoutSession] = [:]
        var exerciseOrder: [String: [String: Int]] = [:]
        var setCounts: [String: Int] = [:]
        var created = 0

        for row in rows.dropFirst() {
            guard let date = parseDate(cell(row, dateCol)) else { continue }
            let key = "\(date.timeIntervalSince1970)|\(cell(row, titleCol))"
            if sessions[key] == nil {
                if existing.contains(where: { abs($0.timeIntervalSince(date)) < 60 }) { continue }
                let session = WorkoutSession(date: date, week: 1, template: nil)
                session.finishedAt = parseDate(cell(row, endCol)) ?? date.addingTimeInterval(3600)
                session.notes = cell(row, titleCol)
                context.insert(session)
                sessions[key] = session
                created += 1
            }
            guard let session = sessions[key] else { continue }
            let name = cell(row, exerciseCol).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let exercise: Exercise
            if let found = exercises[name.lowercased()] {
                exercise = found
            } else {
                exercise = Exercise(name: name, primary: guessMuscle(name), isCustom: true)
                context.insert(exercise)
                exercises[name.lowercased()] = exercise
            }
            var order = exerciseOrder[key] ?? [:]
            let position = order[name] ?? order.count
            order[name] = position
            exerciseOrder[key] = order
            let setKey = "\(key)|\(name)"
            let index = setCounts[setKey, default: 0]
            setCounts[setKey] = index + 1

            let set = SetEntry(exercise: exercise, exerciseOrder: position, setIndex: index)
            set.weight = Double(cell(row, weightCol).replacingOccurrences(of: ",", with: ".")) ?? 0
            set.repsValue = Double(cell(row, repsCol)) ?? 0
            set.isDone = true
            set.isWarmup = cell(row, typeCol).lowercased() == "warmup"
            if let rpe = Double(cell(row, rpeCol)) { set.rir = max(0, Int((10 - rpe).rounded())) }
            set.session = session
            context.insert(set)
        }
        try context.save()
        return created
    }

    enum ImportError: LocalizedError {
        case unknownFormat
        var errorDescription: String? { "Не разпознавам формата. Поддържат се CSV от Strong и Hevy." }
    }
}
