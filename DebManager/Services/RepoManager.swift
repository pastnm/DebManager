import Foundation
import SwiftUI

@MainActor
class RepoManager: ObservableObject {
    static let shared = RepoManager()

    @Published var repos: [Repo] = []
    @Published var repoPackages: [String: [Package]] = [:]
    @Published var isRefreshing = false

    private let network = NetworkManager.shared

    private var reposFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("repos.json")
    }

    private init() {
        loadRepos()
    }

    // MARK: - Add Repo
    func addRepo(url: String) async {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var cleanURL = trimmed
        if !cleanURL.hasPrefix("http://") && !cleanURL.hasPrefix("https://") {
            cleanURL = "https://" + cleanURL
        }
        if !cleanURL.hasSuffix("/") { cleanURL += "/" }

        guard !repos.contains(where: { $0.url == cleanURL }) else { return }

        let domain = URL(string: cleanURL)?.host ?? cleanURL

        var repo = Repo(
            id: UUID(),
            name: domain,
            url: cleanURL,
            iconURL: nil,
            repoDescription: nil,
            packageCount: 0,
            isDefault: false
        )

        repos.append(repo)
        saveRepos()

        // Fetch Release file for name + icon
        if let info = await network.fetchRepoInfo(repoURL: cleanURL) {
            if let index = repos.firstIndex(where: { $0.id == repo.id }) {
                if !info.name.isEmpty { repos[index].name = info.name }
                repos[index].iconURL = info.iconURL
                repos[index].repoDescription = info.description
                repo = repos[index]
                saveRepos()
            }
        }

        await refreshRepo(repo)
    }

    // MARK: - Remove Repo
    func removeRepo(_ repo: Repo) {
        repos.removeAll { $0.id == repo.id }
        repoPackages.removeValue(forKey: repo.url)
        saveRepos()
    }

    // MARK: - Refresh Single Repo
    func refreshRepo(_ repo: Repo) async {
        do {
            let packages = try await network.fetchRepoPackages(repoURL: repo.url)

            // Sort alphabetically by name
            let sorted = packages.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            repoPackages[repo.url] = sorted

            if let index = repos.firstIndex(where: { $0.id == repo.id }) {
                repos[index].packageCount = sorted.count
                saveRepos()
            }
        } catch {
            print("Failed to refresh \(repo.name): \(error)")
        }
    }

    // MARK: - Get Packages for Repo (already sorted)
    func packages(for repo: Repo) -> [Package] {
        return repoPackages[repo.url] ?? []
    }

    // MARK: - Search across all repos by name
    func searchAllRepos(query: String) -> [Package] {
        let q = query.lowercased()
        var results: [Package] = []
        for (_, packages) in repoPackages {
            results.append(contentsOf: packages.filter { $0.name.lowercased().contains(q) })
        }
        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Persistence
    private func saveRepos() {
        if let data = try? JSONEncoder().encode(repos) {
            try? data.write(to: reposFileURL)
        }
    }

    private func loadRepos() {
        if let data = try? Data(contentsOf: reposFileURL),
           let saved = try? JSONDecoder().decode([Repo].self, from: data) {
            repos = saved
        } else {
            repos = []
        }
    }
}
