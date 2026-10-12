import SwiftUI
import SwiftData

struct WorkoutsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Mesocycle.startDate, order: .reverse) private var mesocycles: [Mesocycle]
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @State private var activeSession: WorkoutSession?

    /// Текущият мезоцикъл е най-новият по начална дата.
    private var current: Mesocycle? { mesocycles.first }
    private var unfinished: WorkoutSession? { sessions.first { !$0.isFinished } }
    private var finished: [WorkoutSession] { sessions.filter(\.isFinished) }

    var body: some View {
        NavigationStack {
            List {
                if let unfinished {
                    Section {
                        Button {
                            activeSession = unfinished
                        } label: {
                            Label("Продължи: \(unfinished.title)", systemImage: "play.circle.fill")
                                .font(.headline)
                        }
                    }
                }

                if let current {
                    Section {
                        ForEach(current.sortedTemplates) { template in
                            NavigationLink {
                                MesoGridView(template: template, activeSession: $activeSession)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(template.name).font(.headline)
                                    Text("\(template.items.count) упражнения")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("\(current.name) · седмица \(current.currentWeek) от \(current.weekCount)")
                    }
                } else {
                    Section {
                        Text("Още няма мезоцикъл. Създай или импортирай такъв от „Мезоцикли и сплит“.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    NavigationLink {
                        MesocycleListView(activeSession: $activeSession)
                    } label: {
                        Label("Мезоцикли и сплит", systemImage: "square.stack.3d.up")
                    }
                }

                Section("История") {
                    if finished.isEmpty {
                        Text("Още няма завършени тренировки.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(finished.prefix(30)) { session in
                        NavigationLink {
                            SessionSummaryView(session: session)
                        } label: {
                            SessionRow(session: session)
                        }
                    }
                }

                Section {
                } footer: {
                    Text("Версия v45")
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Тренировки")
            .profileButton()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        ExerciseLibraryView()
                    } label: {
                        Label("Упражнения", systemImage: "list.bullet")
                    }
                }
            }
            .fullScreenCover(item: $activeSession) { session in
                ActiveWorkoutView(session: session)
            }
        }
    }
}

struct SessionRow: View {
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title).font(.headline)
            Text("\(session.date.formatted(date: .abbreviated, time: .shortened)) · седмица \(session.week)")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(session.exerciseGroups) { group in
                let done = group.sets.filter(\.isWorkSet)
                if !done.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(group.exercise?.name ?? "Упражнение")
                            .font(.caption.weight(.semibold))
                        Text(done.map { "\($0.weight.short) кг × \($0.reps)" }.joined(separator: "  ·  "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text("Обем \(WorkoutMath.totalVolume(session.sets).short) кг · \(WorkoutMath.totalReps(session.sets)) повт.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct NewMesocycleSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Мезоцикъл 1"
    @State private var weeks = 4

    var body: some View {
        NavigationStack {
            Form {
                TextField("Име", text: $name)
                Stepper("Седмици: \(weeks)", value: $weeks, in: 1...12)
                Text("Ще създам 4 тренировки: Upper 1, Lower 1, Upper 2, Lower 2. Можеш да ги преименуваш и да добавиш упражнения.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Нов мезоцикъл")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отказ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Създай") {
                        WorkoutService.createMesocycle(name: name, weeks: weeks, in: context)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// Управление на мезоцикли и сплит: списък, нов, импорт, следващ мезоцикъл, имена и тренировки.
struct MesocycleListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Mesocycle.startDate, order: .reverse) private var mesocycles: [Mesocycle]
    @Binding var activeSession: WorkoutSession?
    @State private var showingNewMeso = false
    @State private var importError: String?

    var body: some View {
        List {
            Section {
                if mesocycles.isEmpty {
                    Text("Създай първия си мезоцикъл с бутона +.")
                        .foregroundStyle(.secondary)
                }
                ForEach(mesocycles) { meso in
                    NavigationLink {
                        MesocycleDetailView(mesocycle: meso, activeSession: $activeSession)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(meso.name).font(.headline)
                            Text("Седмица \(meso.currentWeek) от \(meso.weekCount) · \(meso.templates.count) тренировки")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(mesocycles[index]) }
                }
            } footer: {
                Text("Най-новият мезоцикъл е текущият и се показва в таба Тренировки.")
            }
        }
        .navigationTitle("Мезоцикли и сплит")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingNewMeso = true
                    } label: {
                        Label("Нов празен мезоцикъл", systemImage: "plus")
                    }
                    Button {
                        importMeso()
                    } label: {
                        Label("Импортирай Meso 22 (от Excel)", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Label("Нов мезоцикъл", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewMeso) {
            NewMesocycleSheet()
        }
        .alert("Импортът не успя", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    private func importMeso() {
        do {
            try MesoImporter.importBundledMeso(in: context)
        } catch {
            importError = error.localizedDescription
        }
    }
}
