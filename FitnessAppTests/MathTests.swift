import Testing
import Foundation
@testable import FitnessApp

// Тестове за математиката. Пускат се автоматично в GitHub Actions (CI) или в Xcode с Cmd+U.

struct RecoveryMathTests {
    @Test func sleepScoreFullNightIsHundred() {
        #expect(RecoveryMath.sleepScore(asleepHours: 8, inBedHours: 8.5) == 100)
    }

    @Test func sleepScoreShortNightIsLower() {
        let score = RecoveryMath.sleepScore(asleepHours: 4, inBedHours: 4.4)
        // 4/8 часа × 0.8 + пълна ефективност × 0.2 = 60
        #expect(abs(score - 60) < 0.01)
    }

    @Test func baselineNeedsThreeValues() {
        #expect(RecoveryMath.Baseline(values: [1, 2]) == nil)
        #expect(RecoveryMath.Baseline(values: [1, 2, 3]) != nil)
    }

    @Test func recoveryAtBaselineIsAboutFifty() {
        let base = RecoveryMath.Baseline(values: [50, 52, 48, 51, 49, 50, 50, 51])!
        let input = RecoveryMath.RecoveryInput(hrv: 50, hrvBaseline: base, rhr: 50, rhrBaseline: base,
                                               respiratory: nil, respiratoryBaseline: nil, sleepScore: 75)
        let value = RecoveryMath.recovery(input)!
        #expect(abs(value - 50) < 10)
    }

    @Test func recoveryNeedsTwoSignals() {
        let input = RecoveryMath.RecoveryInput(sleepScore: 90)
        #expect(RecoveryMath.recovery(input) == nil)
    }
}

struct BodyMathTests {
    @Test func bmi() {
        #expect(abs((BodyMath.bmi(kg: 80, cm: 180) ?? 0) - 24.69) < 0.05)
    }
}

struct EnergyModelTests {
    @Test func slopeOfLinearWeightGain() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let points = (0..<8).map { (date: start.addingTimeInterval(Double($0) * 86_400), kg: 80 + 0.1 * Double($0)) }
        let slope = EnergyModel.slopePerDay(points)
        #expect(abs((slope ?? 0) - 0.1) < 0.001)
    }

    @Test func slopeNeedsFourPointsOverAWeek() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let points = (0..<3).map { (date: start.addingTimeInterval(Double($0) * 86_400), kg: 80.0) }
        #expect(EnergyModel.slopePerDay(points) == nil)
    }

    @Test func realExpenditureFromStableWeightEqualsIntake() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date.now)
        var intake: [Date: Double] = [:]
        var weights: [(date: Date, kg: Double)] = []
        for day in 0..<21 {
            let date = calendar.date(byAdding: .day, value: -day, to: today)!
            intake[date] = 2500
            if day % 3 == 0 { weights.append((date: date.addingTimeInterval(3600), kg: 80)) }
        }
        let real = EnergyModel.realExpenditure(intakeByDay: intake, weights: weights, endingAt: today)
        #expect(abs((real ?? 0) - 2500) < 1)
    }
}

struct KatchTests {
    @Test func katchUsesLeanMassWhenBodyFatKnown() {
        let bmr = BodyMath.bmr(sex: .male, kg: 100, cm: 180, age: 30, bodyFat: 20)
        #expect(abs(bmr - (370 + 21.6 * 80)) < 0.01)
    }

    @Test func fallsBackToMifflinWithoutBodyFat() {
        let bmr = BodyMath.bmr(sex: .male, kg: 80, cm: 180, age: 30)
        #expect(abs(bmr - (800 + 1125 - 150 + 5)) < 0.01)
    }
}

struct RepsTests {
    @Test func fractionalRepsKeepWholeAndFraction() {
        let set = SetEntry(exercise: nil, exerciseOrder: 0, setIndex: 0)
        set.repsValue = 1.5
        #expect(set.reps == 1)
        #expect(abs(set.repsValue - 1.5) < 0.001)
        set.weight = 100
        #expect(abs(set.volume - 150) < 0.001)
    }
}

struct AIFoodInputTests {
    @Test func validFoodValuesAreAccepted() {
        #expect(AIAssistant.isValidFoodInput(name: "Ориз", grams: 150, kcal: 195,
                                             protein: 4, carbs: 42, fat: 0.5))
    }

    @Test func invalidFoodValuesAreRejected() {
        #expect(!AIAssistant.isValidFoodInput(name: "Ориз", grams: -10, kcal: 195,
                                              protein: 4, carbs: 42, fat: 0.5))
        #expect(!AIAssistant.isValidFoodInput(name: "Ориз", grams: 150, kcal: -.infinity,
                                              protein: 4, carbs: 42, fat: 0.5))
        #expect(!AIAssistant.isValidFoodInput(name: "   ", grams: 150, kcal: 195,
                                              protein: 4, carbs: 42, fat: 0.5))
    }
}
