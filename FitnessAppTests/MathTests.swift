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
        #expect(score < 60 && score > 30)
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
