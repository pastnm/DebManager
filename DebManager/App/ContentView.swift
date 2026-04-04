import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            BrowseView()
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("browse".localized)
                }
                .tag(0)

            DownloadsView()
                .tabItem {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("downloads".localized)
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("settings".localized)
                }
                .tag(2)
        }
        .accentColor(.blue)
    }
}
