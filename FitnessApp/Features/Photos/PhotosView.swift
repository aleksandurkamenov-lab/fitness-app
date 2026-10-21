import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct PhotosView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ProgressPhoto.date, order: .reverse) private var photos: [ProgressPhoto]
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showingPicker = false
    @State private var showingFolder = false
    @State private var importPose: PhotoPose = .front
    @State private var showingPoseDialog = false
    @State private var pendingFolder: URL?
    @State private var filter: PhotoPose?
    @State private var progress: String?

    private var filtered: [ProgressPhoto] {
        guard let filter else { return photos }
        return photos.filter { $0.pose == filter }
    }

    private var groups: [(day: Date, photos: [ProgressPhoto])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { (day: $0, photos: grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Picker("Поза", selection: $filter) {
                    Text("Всички").tag(PhotoPose?.none)
                    ForEach(PhotoPose.allCases) { pose in
                        Text(pose.title).tag(PhotoPose?.some(pose))
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if photos.isEmpty {
                    ContentUnavailableView("Няма снимки", systemImage: "camera",
                                           description: Text("Добави от галерията или от папка с бутона +."))
                        .padding(.top, 40)
                }

                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(groups, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.day, format: .dateTime.day().month(.wide).year())
                                .font(.headline)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                                ForEach(group.photos) { photo in
                                    NavigationLink {
                                        PhotoDetailView(photo: photo)
                                    } label: {
                                        PhotoThumb(photo: photo)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Снимки")
            .safeAreaInset(edge: .bottom) {
                if let progress {
                    Text(progress)
                        .font(.footnote)
                        .padding(8)
                        .background(.regularMaterial, in: Capsule())
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        PhotoCompareView(photos: photos)
                    } label: {
                        Label("Сравни", systemImage: "rectangle.split.2x1")
                    }
                    .disabled(photos.count < 2)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingPicker = true
                        } label: {
                            Label("От галерията", systemImage: "photo.on.rectangle")
                        }
                        Button {
                            showingFolder = true
                        } label: {
                            Label("От папка (Файлове)", systemImage: "folder")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .profileButton()
            .photosPicker(isPresented: $showingPicker, selection: $pickerItems, maxSelectionCount: 50,
                          matching: .images, photoLibrary: .shared())
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                pendingFolder = nil
                showingPoseDialog = true
            }
            .confirmationDialog("Каква поза са снимките?", isPresented: $showingPoseDialog, titleVisibility: .visible) {
                ForEach(PhotoPose.allCases) { pose in
                    Button(pose.title) {
                        importPose = pose
                        if let folder = pendingFolder {
                            pendingFolder = nil
                            Task { await importFolder(folder) }
                        } else {
                            let items = pickerItems
                            Task { await importPicked(items) }
                        }
                    }
                }
                Button("Отказ", role: .cancel) {
                    pickerItems = []
                    pendingFolder = nil
                }
            }
            .fileImporter(isPresented: $showingFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    pendingFolder = url
                    showingPoseDialog = true
                }
            }
        }
    }

    private var knownSources: Set<String> {
        Set(photos.map(\.sourceName).filter { !$0.isEmpty })
    }

    private func importPicked(_ items: [PhotosPickerItem]) async {
        let known = knownSources
        var added = 0
        for (index, item) in items.enumerated() {
            progress = "Внасяне \(index + 1) от \(items.count)…"
            let source = item.itemIdentifier.map { "lib:" + $0 } ?? ""
            if !source.isEmpty && known.contains(source) { continue }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let prepared = PhotoImport.prepare(data, fallbackDate: .now) else { continue }
            context.insert(ProgressPhoto(date: prepared.date, imageData: prepared.data, thumbData: prepared.thumb,
                                         pose: importPose, sourceName: source))
            added += 1
        }
        pickerItems = []
        await finish(added: added)
    }

    private func importFolder(_ folder: URL) async {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        let known = knownSources
        let files = PhotoImport.filesInFolder(folder)
        let legacyCounts = Dictionary(grouping: files, by: { "file:\(folder.lastPathComponent)/\($0.url.lastPathComponent)" })
        var added = 0
        for (index, file) in files.enumerated() {
            progress = "Внасяне \(index + 1) от \(files.count)…"
            await Task.yield()
            // Full normalized path avoids collisions between same-named folders/files.
            let source = "file:" + file.url.standardizedFileURL.path
            let legacySource = "file:\(folder.lastPathComponent)/\(file.url.lastPathComponent)"
            if known.contains(source) || (legacyCounts[legacySource]?.count == 1 && known.contains(legacySource)) { continue }
            guard let data = try? Data(contentsOf: file.url),
                  let prepared = PhotoImport.prepare(data, fallbackDate: file.created) else { continue }
            context.insert(ProgressPhoto(date: prepared.date, imageData: prepared.data, thumbData: prepared.thumb,
                                         pose: importPose, sourceName: source))
            added += 1
        }
        await finish(added: added)
    }

    private func finish(added: Int) async {
        try? context.save()
        progress = "Добавени: \(added)"
        try? await Task.sleep(for: .seconds(3))
        progress = nil
    }
}

private struct PhotoThumb: View {
    let photo: ProgressPhoto

    var body: some View {
        Color.secondary.opacity(0.15)
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                if let image = UIImage(data: photo.thumbData.isEmpty ? photo.imageData : photo.thumbData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .bottomLeading) {
                Text(photo.pose.title)
                    .font(.caption2)
                    .padding(3)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .padding(3)
            }
    }
}

private struct PhotoDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var photo: ProgressPhoto

    var body: some View {
        List {
            Section {
                if let image = UIImage(data: photo.imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
            }
            Section {
                DatePicker("Дата", selection: $photo.date, displayedComponents: .date)
                Picker("Поза", selection: Binding(get: { photo.pose }, set: { photo.pose = $0 })) {
                    ForEach(PhotoPose.allCases) { pose in
                        Text(pose.title).tag(pose)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section {
                Button("Изтрий снимката", role: .destructive) {
                    let doomed = photo
                    dismiss()
                    context.delete(doomed)
                    try? context.save()
                }
            }
        }
        .navigationTitle(Text(photo.date, format: .dateTime.day().month().year()))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Две дати една до друга, за избраната поза.
private struct PhotoCompareView: View {
    let photos: [ProgressPhoto]
    @State private var pose: PhotoPose = .front
    @State private var firstDay: Date?
    @State private var secondDay: Date?

    private var days: [Date] {
        let calendar = Calendar.current
        let set = Set(photos.filter { $0.pose == pose }.map { calendar.startOfDay(for: $0.date) })
        return set.sorted(by: >)
    }

    private func photo(on day: Date?) -> ProgressPhoto? {
        guard let day else { return nil }
        return photos.first { $0.pose == pose && Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("Поза", selection: $pose) {
                ForEach(PhotoPose.allCases) { pose in
                    Text(pose.title).tag(pose)
                }
            }
            .pickerStyle(.segmented)

            HStack(alignment: .top, spacing: 8) {
                column(selection: $firstDay)
                column(selection: $secondDay)
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Сравнение")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: resetDays)
        .onChange(of: pose) { _, _ in resetDays() }
    }

    private func resetDays() {
        firstDay = days.last
        secondDay = days.first
    }

    private func column(selection: Binding<Date?>) -> some View {
        VStack(spacing: 6) {
            Picker("Дата", selection: selection) {
                Text("—").tag(Date?.none)
                ForEach(days, id: \.self) { day in
                    Text(day, format: .dateTime.day().month(.abbreviated).year(.twoDigits)).tag(Date?.some(day))
                }
            }
            .pickerStyle(.menu)
            if let photo = photo(on: selection.wrappedValue), let image = UIImage(data: photo.imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Color.secondary.opacity(0.15)
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay { Text("Няма снимка").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
