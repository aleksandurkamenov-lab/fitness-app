import SwiftUI
import SwiftData

struct MesocycleDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var mesocycle: Mesocycle
    @Binding var activeSession: WorkoutSession?

    var body: some View {
        List {
            Section {
                TextField("Име", text: $mesocycle.name)
                DatePicker("Начало", selection: $mesocycle.startDate, displayedComponents: .date)
                Stepper("Седмици: \(mesocycle.weekCount)", value: $mesocycle.weekCount, in: 1...12)
            } footer: {
                Text("Сега е седмица \(mesocycle.currentWeek).")
            }

            Section("Тренировки") {
                ForEach(mesocycle.sortedTemplates) { template in
                    NavigationLink {
                        TemplateDetailView(template: template, activeSession: $activeSession)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(template.name).font(.headline)
                            Text("\(template.items.count) упражнения")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    let sorted = mesocycle.sortedTemplates
                    for index in offsets { context.delete(sorted[index]) }
                }
                Button {
                    let template = WorkoutTemplate(name: "Тренировка \(mesocycle.templates.count + 1)",
                                                   order: (mesocycle.templates.map(\.order).max() ?? -1) + 1)
                    template.mesocycle = mesocycle
                    context.insert(template)
                } label: {
                    Label("Добави тренировка", systemImage: "plus")
                }
            }
        }
        .navigationTitle(mesocycle.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
