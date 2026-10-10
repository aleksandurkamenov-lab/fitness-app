import SwiftUI

/// Временен екран, докато съответната част не е направена.
struct PlaceholderView: View {
    let title: LocalizedStringKey
    let systemImage: String
    let description: LocalizedStringKey

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
                .navigationTitle(title)
        }
    }
}
