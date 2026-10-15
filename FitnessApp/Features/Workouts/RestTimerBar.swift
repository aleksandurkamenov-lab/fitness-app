import SwiftUI

/// Лента с таймера за почивка (ползва се от седмичната таблица).
struct RestTimerBar: View {
    let timer: RestTimer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let remaining = timer.remaining(at: context.date)
            HStack {
                Image(systemName: "timer")
                Text(remaining > 0 ? "Почивка" : "Почивката свърши")
                Spacer()
                Text(Duration.seconds(remaining.rounded(.up)), format: .time(pattern: .minuteSecond))
                    .monospacedDigit()
                    .font(.title3.weight(.semibold))
                Button("+15") { timer.add(seconds: 15) }
                    .buttonStyle(.bordered)
                Button {
                    timer.stop()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(.thinMaterial)
        }
    }
}
