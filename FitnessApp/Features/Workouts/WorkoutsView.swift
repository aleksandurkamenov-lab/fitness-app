import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct WorkoutsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Mesocycle.startDate, order: .reverse) private var mesocycles: [Mesocycle]
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @State private var pickingFile = false
    @State private var pickingLink = false
    @State private var importError: String?

    /// Текущият мезоцикъл е най-новият по начална дата.
    private var current: Mesocycle? { mesocycles.first }
    private var finished: [WorkoutSession] { sessions.filter(\.isFinished) }

    var body: some View {
        NavigationStack {
            List {
                if let current {
                    Section {
                        ForEach(current.sortedTemplates) { template in
                            NavigationLink {
                                MesoGridView(template: template)
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
                        MesocycleListView()
                    } label: {
                        Label("Мезоцикли и сплит", systemImage: "square.stack.3d.up")
                    }
                    Button {
                        pickingFile = true
                    } label: {
                        Label("Импортирай от Excel файл", systemImage: "doc.badge.plus")
                    }
                    Button {
                        pickingLink = true
                    } label: {
                        Label("Импортирай от Google Sheets линк", systemImage: "link")
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
                    Text("Версия v79")
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Тренировки")
            .profileButton()
            .excelImport(isPresented: $pickingFile, linkPresented: $pickingLink, error: $importError)
            .alert("Импортът не успя", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
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
                        Text(done.map { "\($0.weight.short) кг × \($0.repsText)" }.joined(separator: "  ·  "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text("Обем \(WorkoutMath.totalVolume(session.sets).short) кг · \(WorkoutMath.totalReps(session.sets).short) повт.")
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
    @State private var showingNewMeso = false
    @State private var importError: String?
    @State private var pickingFile = false
    @State private var pickingLink = false

    var body: some View {
        List {
            Section {
                if mesocycles.isEmpty {
                    Text("Създай първия си мезоцикъл с бутона +.")
                        .foregroundStyle(.secondary)
                }
                ForEach(mesocycles) { meso in
                    NavigationLink {
                        MesocycleDetailView(mesocycle: meso)
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
                    Button {
                        pickingFile = true
                    } label: {
                        Label("Импортирай от Excel файл…", systemImage: "doc.badge.plus")
                    }
                    Button {
                        pickingLink = true
                    } label: {
                        Label("Импортирай от Google Sheets линк…", systemImage: "link")
                    }
                } label: {
                    Label("Нов мезоцикъл", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewMeso) {
            NewMesocycleSheet()
        }
        .excelImport(isPresented: $pickingFile, linkPresented: $pickingLink, error: $importError)
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

/// Избор на .xlsx файл, избор на лист и импорт като нов мезоцикъл.
private struct ExcelImportModifier: ViewModifier {
    @Environment(\.modelContext) private var context
    @Binding var isPresented: Bool
    @Binding var linkPresented: Bool
    @Binding var error: String?
    @State private var link = ""
    @State private var workbook: XlsxWorkbook?
    @State private var sheetNames: [String] = []

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: [UTType(filenameExtension: "xlsx") ?? .data]) { result in
                openWorkbook(result)
            }
            .alert("Google Sheets линк", isPresented: $linkPresented) {
                TextField("https://docs.google.com/spreadsheets/d/…", text: $link)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Отказ", role: .cancel) {}
                Button("Импортирай") { Task { await openLink() } }
            } message: {
                Text("Таблицата трябва да е споделена „всеки с линка може да преглежда“. Мога да чета само .xlsx формат на Google Sheets.")
            }
            .sheet(isPresented: Binding(get: { workbook != nil }, set: { if !$0 { workbook = nil } })) {
                NavigationStack {
                    List {
                        Section {
                            ForEach(sheetNames, id: \.self) { name in
                                Button(name) { importSheet(name) }
                            }
                        } header: {
                            Text("Избери мезоцикъл за импорт")
                        } footer: {
                            Text("Очаквам формата на треньорския Excel. Импортира се един лист като нов мезоцикъл.")
                        }
                    }
                    .navigationTitle("Листове")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Отказ") { workbook = nil }
                        }
                    }
                }
            }
    }

    private func openLink() async {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: "/d/") else {
            error = "Не разпознах Google Sheets линка."
            return
        }
        let id = String(trimmed[range.upperBound...].prefix(while: { $0 != "/" && $0 != "?" && $0 != "#" }))
        guard !id.isEmpty,
              let url = URL(string: "https://docs.google.com/spreadsheets/d/\(id)/export?format=xlsx") else {
            error = "Не разпознах Google Sheets линка."
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.starts(with: [0x50, 0x4B]) else {
                error = "Таблицата не се изтегли. Провери дали е споделена с линк за преглед."
                return
            }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("sheets-import.xlsx")
            try data.write(to: file)
            let opened = try XlsxWorkbook(url: file)
            let names = MesoImporter.mesoSheetNames(in: opened)
            sheetNames = names.isEmpty ? opened.sheetNames : names.reversed()
            workbook = opened
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func openWorkbook(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let opened = try XlsxWorkbook(url: url)
            let names = MesoImporter.mesoSheetNames(in: opened)
            sheetNames = names.isEmpty ? opened.sheetNames : names.reversed()
            workbook = opened
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func importSheet(_ name: String) {
        guard let workbook else { return }
        do {
            try MesoImporter.importSheet(named: name, from: workbook, in: context)
            self.workbook = nil
        } catch {
            self.workbook = nil
            self.error = error.localizedDescription
        }
    }
}

extension View {
    func excelImport(isPresented: Binding<Bool>, linkPresented: Binding<Bool>, error: Binding<String?>) -> some View {
        modifier(ExcelImportModifier(isPresented: isPresented, linkPresented: linkPresented, error: error))
    }
}
