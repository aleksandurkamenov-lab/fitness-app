import SwiftUI

/// Главната навигация: един таб за всяка голяма част от приложението.
struct RootTabView: View {
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
    }
}

#Preview {
    RootTabView()
}
