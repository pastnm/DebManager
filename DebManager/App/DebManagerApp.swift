import SwiftUI

@main
struct DebManagerApp: App {
    @StateObject private var downloadManager = DownloadManager.shared
    @StateObject private var repoManager = RepoManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(downloadManager)
                .environmentObject(repoManager)
                .preferredColorScheme(.dark)
        }
    }
}
