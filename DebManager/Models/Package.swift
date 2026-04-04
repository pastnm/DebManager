import Foundation

enum ArchType: String, Codable, CaseIterable, Identifiable {
    case rootful = "rootful"
    case rootless = "rootless"
    case roothide = "roothide"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rootful: return "Rootful (arm)"
        case .rootless: return "Rootless (arm64)"
        case .roothide: return "Roothide (arm64e)"
        }
    }

    var archString: String {
        switch self {
        case .rootful: return "iphoneos-arm"
        case .rootless: return "iphoneos-arm64"
        case .roothide: return "iphoneos-arm64e"
        }
    }

    static func from(architecture: String) -> ArchType {
        let arch = architecture.lowercased()
        if arch.contains("arm64e") { return .roothide }
        if arch.contains("arm64") { return .rootless }
        return .rootful
    }
}

struct Package: Identifiable, Codable, Hashable {
    let uid: String  // truly unique per entry
    let name: String
    let bundleID: String
    let version: String
    let description: String
    let author: String
    let section: String
    let size: String
    let architecture: String
    let filename: String
    let repoURL: String
    let iconURL: String?
    let depiction: String?

    var id: String { uid }

    // Human readable arch label
    var archLabel: String {
        let a = architecture.lowercased()
        if a.contains("arm64e") { return "arm64e" }
        if a.contains("arm64") { return "arm64" }
        if a.contains("arm") { return "arm" }
        return architecture
    }

    var sizeFormatted: String {
        if let bytes = Int(size), bytes > 0 {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: Int64(bytes))
        }
        return size
    }

    init(name: String, bundleID: String, version: String, description: String,
         author: String, section: String, size: String, architecture: String,
         filename: String, repoURL: String, iconURL: String?, depiction: String?) {
        self.uid = UUID().uuidString
        self.name = name
        self.bundleID = bundleID
        self.version = version
        self.description = description
        self.author = author
        self.section = section
        self.size = size
        self.architecture = architecture
        self.filename = filename
        self.repoURL = repoURL
        self.iconURL = iconURL
        self.depiction = depiction
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(uid)
    }

    static func == (lhs: Package, rhs: Package) -> Bool {
        lhs.uid == rhs.uid
    }
}

struct DownloadedPackage: Identifiable, Codable {
    let id: UUID
    let package: Package
    var archType: ArchType
    let downloadDate: Date
    var localPath: String

    var fileName: String {
        "\(package.bundleID)_\(package.version)_\(archType.archString).deb"
    }
}
