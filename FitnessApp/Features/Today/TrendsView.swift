import SwiftUI
import SwiftData
import Charts

/// Графики на показателите във времето: тегло, HRV, сън, пулс, възстановяване, натоварване и др.
struct TrendsView: View {
    @Query(sort: \DailyMetric.day) private var metrics: [DailyMetric]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query private var profiles: [UserProfile]
    @State private var rangeDays = 30

    private var from: Date {
        Calendar.current.date(byAdding: .day, value: -rangeDays, to: Calendar.current.startOfDay(for: .now)) ?? .distantPast
    }

    private func series(_ kind: MetricKind) -> [DayValue] {
        MetricSeries.series(kind, in: metrics, from: from)
    }

    private var weightPoints: [BodyMath.TrendPoint] {
        BodyMath.trend(weights).filter { $0.date >= from }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ActivityStatsCard()

                Picker("Период", selection: $rangeDays) {
                    Text("7 дни").tag(7)
                    Text("30 дни").tag(30)
                    Text("90 дни").tag(90)
                }
                .pickerStyle(.segmented)

                if weightPoints.count >= 2, let last = weightPoints.last {
                    card(title: "Тегло", latest: "\(last.kg.short) кг",
                         detail: "тренд \(last.trend.short) кг") {
                        WeightChart(points: weightPoints, goalKg: profiles.first?.goalWeightKg)
                    }
                }

                NavigationLink {
                    MuscleBalanceView()
                } label: {
                    HStack {
                        Label("Баланс и умора по мускули", systemImage: "figure.strengthtraining.traditional")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.background, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)

                NavigationLink {
                    StrengthProgressView()
                } label: {
                    HStack {
                        Label("Силов прогрес", systemImage: "dumbbell")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.background, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)

                ForEach(MetricKind.allCases.filter { $0 != .strengthSessions && $0 != .cardioSessions }) { kind in
                    let data = series(kind)
                    if data.count >= 2, let last = data.last {
                        let average = data.map(\.value).reduce(0, +) / Double(data.count)
                        card(title: kind.title,
                             latest: "\(format(last.value, kind)) \(kind.unit)",
                             detail: "средно \(format(average, kind))") {
                            Chart(data) { point in
                                LineMark(x: .value("Ден", point.day), y: .value(kind.title, point.value))
                                    .interpolationMethod(.catmullRom)
                                PointMark(x: .value("Ден", point.day), y: .value(kind.title, point.value))
                                    .symbolSize(20)
                                RuleMark(y: .value("Средно", average))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                                    .foregroundStyle(.secondary)
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .chartScrub(data.map { ScrubPoint(date: $0.day, value: $0.value, text: "\(scrubDate($0.day)): \(format($0.value, kind)) \(kind.unit)") })
                            .padding(.top, 24)
                            .frame(height: 164)
                        }
                    }
                }

                if metrics.isEmpty && weights.count < 2 {
                    Text("Още няма история. Свържи WHOOP или Apple Health в таб Днес и плъзни надолу за опресняване.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Тенденции")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func format(_ value: Double, _ kind: MetricKind) -> String {
        value.formatted(.number.precision(.fractionLength(kind.digits)))
    }

    private func card<Content: View>(title: String, latest: String, detail: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                VStack(alignment: .trailing) {
                    Text(latest).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}
