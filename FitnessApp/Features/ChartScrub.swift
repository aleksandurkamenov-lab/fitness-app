import SwiftUI
import Charts

/// Точка, която може да се избере с пръст върху графика.
struct ScrubPoint {
    let date: Date
    let value: Double
    let text: String
}

private struct ChartScrub: ViewModifier {
    let points: [ScrubPoint]
    @State private var selected: Date?

    private var nearest: ScrubPoint? {
        guard let selected else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }
    }

    func body(content: Content) -> some View {
        content
            .chartXSelection(value: $selected)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    if let point = nearest,
                       let plot = proxy.plotFrame,
                       let x = proxy.position(forX: point.date),
                       let y = proxy.position(forY: point.value) {
                        let frame = geo[plot]
                        let px = frame.origin.x + x
                        let py = frame.origin.y + y
                        Path { path in
                            path.move(to: CGPoint(x: px, y: frame.minY))
                            path.addLine(to: CGPoint(x: px, y: frame.maxY))
                        }
                        .stroke(.secondary.opacity(0.6), lineWidth: 1)
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 10, height: 10)
                            .position(x: px, y: py)
                        Text(point.text)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .fixedSize()
                            .position(x: min(max(px, 70), geo.size.width - 70), y: max(frame.minY - 2, 10))
                    }
                }
                .allowsHitTesting(false)
            }
    }
}

extension View {
    /// Натисни и плъзни по графиката, за да видиш точната стойност за ден.
    func chartScrub(_ points: [ScrubPoint]) -> some View {
        modifier(ChartScrub(points: points))
    }
}

func scrubDate(_ date: Date) -> String {
    date.formatted(.dateTime.day().month(.abbreviated).year())
}
