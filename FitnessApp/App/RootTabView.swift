import SwiftUI
import SwiftData

/// Главната навигация: един таб за всяка голяма част от приложението.
struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            Tab("Днес", systemImage: "heart.text.square") {
                TodayView()
            }
            Tab("Тренировки", systemImage: "dumbbell") {
                WorkoutsView()
            }
            Tab("Хранене", systemImage: "fork.knife") {
                NutritionView()
            }
            Tab("Мерки", systemImage: "ruler") {
                MeasurementsView()
            }
            Tab("Снимки", systemImage: "camera") {
                PhotosView()
            }
        }
        .onAppear {
            ExerciseLibrary.seedIfNeeded(context)
        }
        .task(id: scenePhase) {
            // При отваряне: качва, ако е минало време; при излизане: качва винаги, за да са свежи данните за треньора.
            if scenePhase == .active {
                await ClientCleanup.run(context: context)
                await CloudService.shared.syncIfNeeded(context: context)
            }
            if scenePhase == .background { await CloudService.shared.syncIfNeeded(context: context, force: true) }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Exercise.self, Mesocycle.self, WorkoutSession.self], inMemory: true)
}
