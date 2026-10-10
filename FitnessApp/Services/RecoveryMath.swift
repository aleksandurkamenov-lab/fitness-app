import Foundation

/// Собствени оценки за сън, възстановяване и натоварване. Не са оценките на WHOOP или Polar.
enum RecoveryMath {
    struct Baseline {
        var mean: Double
        var sd: Double
        var count: Int

        /// Достатъчно дни за смислено сравнение.
        var isReliable: Bool { count >= 7 && sd > 0 }

        init?(values: [Double]) {
            guard values.count >= 3 else { return nil }
            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
            self.mean = mean
            // Минимално разсейване, за да не избухват z-оценките при много равни стойности.
            self.sd = max(variance.squareRoot(), abs(mean) * 0.03)
            self.count = values.count
        }

        func z(_ value: Double) -> Double { max(-2.5, min(2.5, (value - mean) / sd)) }
    }

    enum Status {
        case normal, high, low

        var title: String {
            switch self {
            case .normal: "в нормата"
            case .high: "над нормата"
            case .low: "под нормата"
            }
        }
    }

    /// В нормата = в рамките на 1 стандартно отклонение от личната средна.
    static func status(_ value: Double, baseline: Baseline?) -> Status? {
        guard let baseline, baseline.isReliable else { return nil }
        let z = (value - baseline.mean) / baseline.sd
        if z > 1 { return .high }
        if z < -1 { return .low }
        return .normal
    }

    /// Сън 0–100: 80% продължителност спрямо нуждата, 20% ефективност (сън / време в леглото).
    static func sleepScore(asleepHours: Double, inBedHours: Double?, needHours: Double = 8) -> Double {
        let duration = min(asleepHours / needHours, 1)
        let efficiency: Double
        if let inBedHours, inBedHours > 0 { efficiency = min(asleepHours / inBedHours / 0.9, 1) } else { efficiency = 1 }
        return (duration * 0.8 + efficiency * 0.2) * 100
    }

    struct RecoveryInput {
        var hrv: Double?
        var hrvBaseline: Baseline?
        var rhr: Double?
        var rhrBaseline: Baseline?
        var respiratory: Double?
        var respiratoryBaseline: Baseline?
        var sleepScore: Double?
    }

    /// Възстановяване 0–100 от отклоненията от личната норма. Липсващите данни се пропускат.
    static func recovery(_ input: RecoveryInput) -> Double? {
        var parts: [(weight: Double, z: Double)] = []
        if let hrv = input.hrv, let base = input.hrvBaseline, base.isReliable {
            parts.append((0.45, base.z(hrv)))
        }
        if let rhr = input.rhr, let base = input.rhrBaseline, base.isReliable {
            parts.append((0.25, -base.z(rhr)))
        }
        if let resp = input.respiratory, let base = input.respiratoryBaseline, base.isReliable {
            parts.append((0.10, -base.z(resp)))
        }
        if let sleep = input.sleepScore {
            parts.append((0.20, max(-2.5, min(2.5, (sleep - 75) / 15))))
        }
        // Само сънят не е достатъчен за оценка.
        guard parts.count >= 2 else { return nil }
        let total = parts.reduce(0) { $0 + $1.weight }
        let z = parts.reduce(0) { $0 + $1.weight * $1.z } / total
        return 100 / (1 + exp(-0.9 * z))
    }

    /// Натоварване 0–21 по Banister TRIMP от пулса през деня.
    static func strain(heartRates: [(date: Date, bpm: Double)], restingHR: Double, age: Int) -> Double {
        let maxHR = 208 - 0.7 * Double(age)
        let reserve = max(maxHR - restingHR, 40)
        let sorted = heartRates.sorted { $0.date < $1.date }
        var trimp = 0.0
        for (index, sample) in sorted.enumerated() {
            let next = index + 1 < sorted.count ? sorted[index + 1].date : sample.date.addingTimeInterval(60)
            let minutes = min(next.timeIntervalSince(sample.date) / 60, 5)
            let fraction = (sample.bpm - restingHR) / reserve
            guard fraction > 0.2 else { continue }
            let f = min(fraction, 1)
            trimp += minutes * f * 0.64 * exp(1.92 * f)
        }
        return 21 * (1 - exp(-trimp / 150))
    }
}
