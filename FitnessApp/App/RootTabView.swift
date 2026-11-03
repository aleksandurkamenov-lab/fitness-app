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
            DataTransfer.seedUserDexaIfNeeded(in: context)
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await CloudService.shared.syncIfNeeded(context: context) }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Exercise.self, Mesocycle.self, WorkoutSession.self], inMemory: true)
}
