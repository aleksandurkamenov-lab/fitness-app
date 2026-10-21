import SwiftUI
import SwiftData

struct SessionSummaryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: WorkoutSession
    @State private var confirmingDelete = false

    var body: some View {
        List {
            Section {
                LabeledContent("Дата", value: session.date.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Седмица", value: "\(session.week)")
                LabeledContent("Обем", value: "\(WorkoutMath.totalVolume(session.sets).short) кг")
                LabeledContent("Повторения", value: WorkoutMath.totalReps(session.sets).short)
                if let end = session.finishedAt {
                    LabeledContent("Продължителност",
                                   value: Duration.seconds(end.timeIntervalSince(session.date))
                                       .formatted(.time(pattern: .hourMinute)))
                }
            }

            ForEach(session.exerciseGroups) { group in
                Section(group.exercise?.name ?? "Упражнение") {
                    ForEach(group.sets) { set in
                        HStack {
                            Text(set.isWarmup ? "З" : "\(set.setIndex + 1).")
                                .foregroundStyle(.secondary)
                            Text("\(set.weight.short) кг × \(set.repsText)\(set.rir >= 0 ? " · RIR \(set.rir)" : "")")
                            Spacer()
                            Text("1RM ~\(set.estimatedOneRepMax.short)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Обем", value: "\(WorkoutMath.totalVolume(group.sets).short) кг")
                        .font(.caption)
                }
            }

            if !session.notes.isEmpty {
                Section("Бележка") { Text(session.notes) }
            }

            Section {
                Button("Изтрий тренировката", role: .destructive) {
                    confirmingDelete = true
                }
            }
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Да изтрия ли тренировката?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Изтрий", role: .destructive) {
                let doomed = session
                dismiss()
                context.delete(doomed)
                try? context.save()
            }
            Button("Отказ", role: .cancel) {}
        }
    }
}
