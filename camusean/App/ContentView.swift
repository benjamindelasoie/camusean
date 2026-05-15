import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Read", systemImage: "book.fill") {
                ReadingSessionView()
            }
            Tab("Review", systemImage: "rectangle.stack.fill") {
                ReviewView()
            }
            Tab("Settings", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Word.self, inMemory: true)
}
