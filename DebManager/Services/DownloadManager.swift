import Foundation
import SwiftUI

@MainActor
class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published var downloadedPackages: [DownloadedPackage] = []
    @Published var activeDownloads: [String: Double] = [:]
    @Published var toastMessage: String?
    @Published var isBatchConverting = false
    @Published var batchProgress: (current: Int, total: Int, name: String) = (0, 0, "")

    private let fileManager = FileManager.default
    private let network = NetworkManager.shared

    var debsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Debs", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var metadataURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("downloads_metadata.json")
    }

    private init() { loadMetadata() }

    func downloadPackage(_ package: Package) async {
        guard activeDownloads[package.uid] == nil else { return }
        if downloadedPackages.contains(where: {
            $0.package.bundleID == package.bundleID && $0.package.version == package.version && $0.package.architecture == package.architecture
        }) {
            showToast("already_downloaded".localized); return
        }

        activeDownloads[package.uid] = 0.0
        do {
            let localURL = try await network.downloadDeb(package: package, to: debsDirectory) { [weak self] p in
                Task { @MainActor in self?.activeDownloads[package.uid] = p }
            }
            let downloaded = DownloadedPackage(
                id: UUID(), package: package,
                archType: ArchType.from(architecture: package.architecture),
                downloadDate: Date(), localPath: localURL.lastPathComponent
            )
            downloadedPackages.append(downloaded)
            saveMetadata()
            showToast("\(package.name) " + "downloaded_success".localized)
        } catch {
            showToast("download_failed".localized + ": \(error.localizedDescription)")
        }
        activeDownloads.removeValue(forKey: package.uid)
    }

    func deletePackage(_ downloaded: DownloadedPackage) {
        let filePath = debsDirectory.appendingPathComponent(downloaded.localPath)
        try? fileManager.removeItem(at: filePath)
        downloadedPackages.removeAll { $0.id == downloaded.id }
        saveMetadata()
        showToast("deleted".localized)
    }

    func getFileURL(for downloaded: DownloadedPackage) -> URL {
        debsDirectory.appendingPathComponent(downloaded.localPath)
    }

    // MARK: - Single Convert
    func convertPackage(_ downloaded: DownloadedPackage, to target: ArchType) async {
        guard let index = downloadedPackages.firstIndex(where: { $0.id == downloaded.id }) else { return }
        let sourceURL = debsDirectory.appendingPathComponent(downloaded.localPath)

        do {
            let convertedURL = try await DebConverter.shared.convert(
                debAt: sourceURL, from: downloaded.archType, to: target, outputDirectory: debsDirectory
            )
            let updated = DownloadedPackage(
                id: UUID(), package: downloaded.package,
                archType: target, downloadDate: Date(),
                localPath: convertedURL.lastPathComponent
            )
            downloadedPackages.insert(updated, at: index + 1)
            saveMetadata()
            showToast("\(downloaded.package.name) " + "converted_to".localized + " \(target.displayName)")
        } catch {
            showToast("conversion_failed".localized + ": \(error.localizedDescription)")
        }
    }

    // MARK: - Batch Convert
    func convertBatch(packages: [DownloadedPackage], to target: ArchType) async {
        isBatchConverting = true
        let items = packages.map { pkg in
            (url: debsDirectory.appendingPathComponent(pkg.localPath), from: pkg.archType, to: target)
        }

        let results = await DebConverter.shared.convertBatch(packages: items, outputDirectory: debsDirectory) { [weak self] current, total, name in
            Task { @MainActor in
                self?.batchProgress = (current + 1, total, name)
            }
        }

        var successCount = 0
        for (i, result) in results.enumerated() {
            if let url = result.url {
                let original = packages[i]
                let converted = DownloadedPackage(
                    id: UUID(), package: original.package,
                    archType: target, downloadDate: Date(),
                    localPath: url.lastPathComponent
                )
                downloadedPackages.append(converted)
                successCount += 1
            }
        }

        saveMetadata()
        isBatchConverting = false
        batchProgress = (0, 0, "")

        let failCount = results.count - successCount
        if failCount == 0 {
            showToast("\(successCount) " + "packages_converted".localized)
        } else {
            showToast("\(successCount) converted, \(failCount) failed")
        }
    }

    // MARK: - Persistence
    private func saveMetadata() {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(downloadedPackages) { try? data.write(to: metadataURL) }
    }

    private func loadMetadata() {
        guard let data = try? Data(contentsOf: metadataURL) else { return }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        if let packages = try? decoder.decode([DownloadedPackage].self, from: data) {
            downloadedPackages = packages.filter {
                fileManager.fileExists(atPath: debsDirectory.appendingPathComponent($0.localPath).path)
            }
        }
    }

    func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.toastMessage = nil }
    }

    func isDownloaded(_ package: Package) -> Bool {
        downloadedPackages.contains {
            $0.package.bundleID == package.bundleID && $0.package.version == package.version && $0.package.architecture == package.architecture
        }
    }

    func progress(for uid: String) -> Double? { activeDownloads[uid] }
}
