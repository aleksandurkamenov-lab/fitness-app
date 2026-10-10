import Foundation

/// Изчисления за тренировките. Стойностите са ориентировъчни.
enum WorkoutMath {
    /// Приблизителен 1RM по Epley: тегло × (1 + повторения / 30).
    static func epley(weight: Double, reps: Int) -> Double {
        guard weight > 0, reps > 0 else { return 0 }
        return reps == 1 ? weight : weight * (1 + Double(reps) / 30)
    }

    static func totalVolume(_ sets: [SetEntry]) -> Double {
        sets.filter(\.isWorkSet).reduce(0) { $0 + $1.volume }
    }

    static func totalReps(_ sets: [SetEntry]) -> Int {
        sets.filter(\.isWorkSet).reduce(0) { $0 + $1.reps }
    }

    /// Най-добрата серия по приблизителен 1RM.
    static func bestSet(_ sets: [SetEntry]) -> SetEntry? {
        sets.filter { $0.isWorkSet && $0.reps > 0 }.max { $0.estimatedOneRepMax < $1.estimatedOneRepMax }
    }

    /// Тежест за загрявка: процент от работната, закръглен до 2,5 кг.
    static func warmupWeight(_ work: Double, percent: Double) -> Double {
        ((work * percent) / 2.5).rounded() * 2.5
    }

    /// Седмичен обем в серии по мускулна група: основната група брои 1, второстепенните 0.5.
    static func weeklySets(_ sets: [SetEntry]) -> [MuscleGroup: Double] {
        var result: [MuscleGroup: Double] = [:]
        for set in sets where set.isWorkSet {
            guard let exercise = set.exercise else { continue }
            result[exercise.primaryMuscle, default: 0] += 1
            for muscle in exercise.secondaryMuscles {
                result[muscle, default: 0] += 0.5
            }
        }
        return result
    }
}

extension Double {
    /// Кратко число без излишни нули: 80, 82.5.
    var short: String {
        formatted(.number.grouping(.never).precision(.fractionLength(0...1)))
    }
}
