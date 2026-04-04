import SwiftUI

struct BrowseView: View {
    @EnvironmentObject var downloadManager: DownloadManager
    @EnvironmentObject var repoManager: RepoManager

    @State private var searchText = ""
    @State private var searchResults: [Package] = []
    @State private var hasSearched = false
    @State private var showAddRepo = false
    @State private var newRepoURL = ""
    @State private var selectedRepo: Repo?
    @State private var repoPackagesList: [Package] = []
    @State private var isLoadingRepo = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        searchBar
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)

                        if let repo = selectedRepo {
                            repoDetailView(repo)
                        } else if hasSearched {
                            searchResultsView
                        } else {
                            defaultView
                        }
                    }
                }

                if let toast = downloadManager.toastMessage {
                    VStack {
                        ToastView(message: toast)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(), value: downloadManager.toastMessage)
                }
            }
            .navigationTitle(selectedRepo?.displayName ?? "browse".localized)
            .navigationBarTitleDisplayMode(.large)
            .navigationBarItems(leading: Group {
                if selectedRepo != nil {
                    Button {
                        withAnimation(.spring()) {
                            selectedRepo = nil
                            repoPackagesList = []
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("back".localized)
                        }
                    }
                }
            })
            .sheet(isPresented: $showAddRepo) { addRepoSheet }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Search Bar
    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.gray)
                TextField("search".localized, text: $searchText, onCommit: { performSearch() })
                    .foregroundColor(.white)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        hasSearched = false
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                    }
                }
            }
            .padding(10)
            .background(Color(white: 0.15))
            .cornerRadius(12)

            Button(action: performSearch) {
                Text("search_btn".localized).fontWeight(.semibold)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color.blue).foregroundColor(.white)
            .cornerRadius(12)
        }
    }

    // MARK: - Default View (no repos yet = empty state, has repos = list them)
    private var defaultView: some View {
        VStack(spacing: 0) {
            if repoManager.repos.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "externaldrive.badge.plus")
                        .font(.system(size: 48)).foregroundColor(.blue.opacity(0.6))
                    Text("no_repos".localized)
                        .font(.system(size: 20, weight: .bold))
                    Text("no_repos_sub".localized)
                        .font(.subheadline).foregroundColor(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 40)

                    Button { showAddRepo = true } label: {
                        Label("add_repo".localized, systemImage: "plus.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .padding(.horizontal, 24).padding(.vertical, 12)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                    .padding(.top, 8)
                }
                .padding(.vertical, 60)
            } else {
                // Repos list
                HStack {
                    Text("repos".localized)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary).textCase(.uppercase)
                    Spacer()
                    Button { showAddRepo = true } label: {
                        Label("add_repo".localized, systemImage: "plus.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 8).padding(.top, 8)

                VStack(spacing: 0) {
                    ForEach(repoManager.repos) { repo in
                        RepoRow(repo: repo) { loadRepo(repo) }
                            onRemove: { repoManager.removeRepo(repo) }
                        Divider().padding(.leading, 72)
                    }
                }
                .background(Color(white: 0.11))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Search Results
    private var searchResultsView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("search_results".localized)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary).textCase(.uppercase)
                Spacer()
                Text("\(searchResults.count)")
                    .font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)

            if searchResults.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40)).foregroundColor(.secondary.opacity(0.5))
                    Text("no_results".localized).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                .padding(.vertical, 60)
            } else {
                VStack(spacing: 0) {
                    ForEach(searchResults) { pkg in
                        PackageRow(package: pkg)
                        Divider().padding(.leading, 66)
                    }
                }
                .background(Color(white: 0.11))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Repo Detail
    private func repoDetailView(_ repo: Repo) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                RepoIcon(repo: repo, size: 56, cornerRadius: 14)
                VStack(alignment: .leading, spacing: 4) {
                    Text(repo.displayName).font(.system(size: 18, weight: .bold))
                    Text(repo.url).font(.system(size: 12)).foregroundColor(.secondary).lineLimit(1)
                    if repo.packageCount > 0 {
                        Text("\(repo.packageCount) " + "packages".localized)
                            .font(.system(size: 12, weight: .medium)).foregroundColor(.blue)
                    }
                }
                Spacer()
            }
            .padding(20)

            if isLoadingRepo {
                VStack(spacing: 12) {
                    ProgressView().scaleEffect(1.2)
                    Text("loading".localized).font(.subheadline).foregroundColor(.secondary)
                }
                .padding(.vertical, 60)
            } else if repoPackagesList.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "shippingbox").font(.system(size: 40)).foregroundColor(.secondary.opacity(0.5))
                    Text("no_results".localized).font(.subheadline).foregroundColor(.secondary)
                }
                .padding(.vertical, 60)
            } else {
                HStack {
                    Text("repo_packages".localized)
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary).textCase(.uppercase)
                    Spacer()
                    Text("\(repoPackagesList.count)").font(.system(size: 13)).foregroundColor(.secondary)
                }
                .padding(.horizontal, 20).padding(.bottom, 8)

                VStack(spacing: 0) {
                    ForEach(repoPackagesList) { pkg in
                        PackageRow(package: pkg)
                        Divider().padding(.leading, 66)
                    }
                }
                .background(Color(white: 0.11))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Add Repo Sheet
    private var addRepoSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("repo_url".localized), footer: Text("add_repo_hint".localized)) {
                    TextField("repo_url".localized, text: $newRepoURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            }
            .navigationTitle("add_repo".localized)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("cancel".localized) { showAddRepo = false; newRepoURL = "" },
                trailing: Button("add".localized) {
                    Task {
                        await repoManager.addRepo(url: newRepoURL)
                        showAddRepo = false; newRepoURL = ""
                    }
                }.disabled(newRepoURL.trimmingCharacters(in: .whitespaces).isEmpty)
            )
        }
    }

    // MARK: - Actions
    private func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        hasSearched = true
        selectedRepo = nil
        searchResults = repoManager.searchAllRepos(query: query)
    }

    private func loadRepo(_ repo: Repo) {
        withAnimation(.spring()) { selectedRepo = repo }
        isLoadingRepo = true

        Task {
            await repoManager.refreshRepo(repo)
            await MainActor.run {
                repoPackagesList = repoManager.packages(for: repo)
                isLoadingRepo = false
            }
        }
    }
}

// MARK: - Repo Icon
struct RepoIcon: View {
    let repo: Repo
    var size: CGFloat = 48
    var cornerRadius: CGFloat = 12

    var body: some View {
        if let iconURLString = repo.iconURL, let iconURL = URL(string: iconURLString) {
            AsyncImage(url: iconURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                default: fallbackIcon
                }
            }
        } else {
            fallbackIcon
        }
    }

    private var fallbackIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.blue.opacity(0.1))
                .frame(width: size, height: size)
            Image(systemName: "externaldrive.fill")
                .font(.system(size: size * 0.42)).foregroundColor(.blue)
        }
    }
}

// MARK: - Repo Row
struct RepoRow: View {
    let repo: Repo
    let onBrowse: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RepoIcon(repo: repo, size: 48, cornerRadius: 12)
            VStack(alignment: .leading, spacing: 3) {
                Text(repo.displayName).font(.system(size: 15, weight: .semibold))
                if let desc = repo.repoDescription, !desc.isEmpty {
                    Text(desc).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                } else {
                    Text(repo.url).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                }
                if repo.packageCount > 0 {
                    Text("\(repo.packageCount) " + "packages".localized)
                        .font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                }
            }
            Spacer()
            Button(action: onBrowse) {
                Text("browse_repo".localized)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Color.blue.opacity(0.12)).foregroundColor(.blue)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) { onRemove() } label: {
                Label("remove".localized, systemImage: "trash")
            }
        }
    }
}
