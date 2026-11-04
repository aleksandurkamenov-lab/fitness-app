import Foundation
import SwiftData

/// Еднократни поправки след изчистването на примерното мезо Upper/Lower.
@MainActor
enum ClientCleanup {
    private static let renames: [String: String] = [
        "Barbell Overhead Press (Seated като на видеото в Whatsup)": "Seated Barbell Overhead Press",
        "Pec Dec Machine": "Pec Deck Machine",
        "D handle Cable Lateral Raises": "D-Handle Cable Lateral Raises",
        "Biceps Seated DB curls": "Seated DB Biceps Curls",
        "Reverce Pec Dec": "Reverse Pec Deck",
        "Barbell Trap shrugs": "Barbell Trap Shrugs",
        "Standing Calves Press (unilateral)": "Standing Calf Press (unilateral)",
        "Bayesain Curl": "Bayesian Curl",
        "Adductor machine": "Adductor Machine",
        "Leg Press Calves press": "Leg Press Calf Press",
    ]

    private static let sampleNames: Set<String> = [
        "Seated Barbell Overhead Press",
        "Lat Pulldown (close grip handle)",
        "Pec Deck Machine",
        "D-Handle Cable Lateral Raises",
        "Seated DB Biceps Curls",
        "Triceps Rope Extension",
        "Reverse Pec Deck",
        "RDL",
        "Leg Press",
        "Seated Leg Curl",
        "Barbell Trap Shrugs",
        "Standing Calf Press (unilateral)",
        "Wide Grip Lat Pulldown",
        "Barbell Bench Press",
        "Pendulum Row",
        "Lateral Shoulder Machine",
        "Bayesian Curl",
        "Triceps Unilateral Extension",
        "Face Pulls",
        "Hack Squat",
        "Unilateral Leg Curls",
        "Leg Extension",
        "Adductor Machine",
        "Leg Press Calf Press",
    ]

    /// Вика се при отваряне на приложението. Рекордите се пипат само когато сървърът
    /// потвърди, че акаунтът не е на треньора; без вход или без мрежа не се променя нищо.
    static func run(context: ModelContext) async {
        fixNames(in: context)
        let key = "cleanup.client1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        guard let isCoach = await CloudService.shared.isCoachAccount() else { return }
        if !isCoach { cleanRecords(in: context) }
        UserDefaults.standard.set(true, forKey: key)
    }

    private static func fixNames(in context: ModelContext) {
        let key = "cleanup.names1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let taken = Set(exercises.map(\.name))
        for exercise in exercises {
            if let name = renames[exercise.name], !taken.contains(name) { exercise.name = name }
        }
        let templates = (try? context.fetch(FetchDescriptor<WorkoutTemplate>())) ?? []
        for template in templates where template.name == "Lower Hamm Focus" {
            template.name = "Lower Hamstring Focus"
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Маха рекордите от примерното мезо и слага тези от собствените тренировки на клиента.
    private static func cleanRecords(in context: ModelContext) {
        let allSets = (try? context.fetch(FetchDescriptor<SetEntry>())) ?? []
        var byExercise: [PersistentIdentifier: [SetEntry]] = [:]
        for set in allSets {
            guard let exercise = set.exercise, sampleNames.contains(exercise.name) else { continue }
            set.bestWeight = 0
            set.bestReps = 0
            if set.isWorkSet && set.repsValue > 0 {
                byExercise[exercise.persistentModelID, default: []].append(set)
            }
        }

        let items = (try? context.fetch(FetchDescriptor<TemplateExercise>())) ?? []
        for item in items {
            guard let exercise = item.exercise, sampleNames.contains(exercise.name) else { continue }
            let done = byExercise[exercise.persistentModelID] ?? []
            item.targets = item.targets.enumerated().map { index, target in
                var next = target
                next.bestWeight = nil
                next.bestReps = nil
                let sameSet = done.filter { $0.setIndex == index }
                let pool = sameSet.isEmpty ? done : sameSet
                if let best = pool.max(by: { $0.estimatedOneRepMax < $1.estimatedOneRepMax }) {
                    next.bestWeight = best.weight
                    next.bestReps = best.repsValue
                }
                return next
            }
        }

        let mesos = (try? context.fetch(FetchDescriptor<Mesocycle>())) ?? []
        for meso in mesos where meso.name.hasPrefix("Meso ") && meso.name.hasSuffix("Upper/Lower") {
            meso.name = "Upper/Lower"
        }

        // DEXA на треньора, записвана по погрешка на всяко устройство.
        let scans = (try? context.fetch(FetchDescriptor<BodyScan>())) ?? []
        for scan in scans where scan.kind == "DEXA" && scan.weightKg == 94 && scan.bodyFatPercent == 18 && scan.leanMassKg == 74 {
            context.delete(scan)
        }
        try? context.save()
    }
}
