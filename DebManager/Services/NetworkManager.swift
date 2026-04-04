import Foundation
import Compression

struct RepoInfo {
    var name: String
    var description: String
    var iconURL: String?
}

class NetworkManager {
    static let shared = NetworkManager()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.httpAdditionalHeaders = [
            "User-Agent": "Telesphoreo APT-HTTP/1.0.592",
            "Accept": "*/*"
        ]
        session = URLSession(configuration: config)
    }

    // MARK: - Fetch Repo Info (Release file for name + icon)
    func fetchRepoInfo(repoURL: String) async -> RepoInfo? {
        let baseURL = repoURL.hasSuffix("/") ? repoURL : repoURL + "/"

        for path in ["Release", "dists/stable/Release"] {
            guard let url = URL(string: baseURL + path) else { continue }
            do {
                let (data, response) = try await session.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      let content = String(data: data, encoding: .utf8) else { continue }

                let fields = parseDebianFields(content)
                let name = fields["Origin"] ?? fields["Label"] ?? fields["Suite"] ?? ""
                let desc = fields["Description"] ?? ""

                var iconURL: String? = nil
                for iconPath in ["CydiaIcon.png", "CydiaIcon@2x.png", "RepoIcon.png"] {
                    if let iconTestURL = URL(string: baseURL + iconPath) {
                        if let (_, iconResp) = try? await session.data(from: iconTestURL),
                           let iconHTTP = iconResp as? HTTPURLResponse,
                           iconHTTP.statusCode == 200 {
                            iconURL = baseURL + iconPath
                            break
                        }
                    }
                }

                if !name.isEmpty {
                    return RepoInfo(name: name, description: desc, iconURL: iconURL)
                }
            } catch { continue }
        }
        return nil
    }

    // MARK: - Fetch ALL Repo Packages
    func fetchRepoPackages(repoURL: String) async throws -> [Package] {
        let baseURL = repoURL.hasSuffix("/") ? repoURL : repoURL + "/"

        // Try ALL common Packages file locations
        let paths = [
            // Flat repo layout
            "Packages",
            "Packages.gz",
            "Packages.bz2",
            "Packages.xz",
            "Packages.zst",
            // Dist-based layout (arm64)
            "dists/stable/main/binary-iphoneos-arm64/Packages",
            "dists/stable/main/binary-iphoneos-arm64/Packages.gz",
            "dists/stable/main/binary-iphoneos-arm64/Packages.bz2",
            "dists/stable/main/binary-iphoneos-arm64/Packages.xz",
            // Dist-based layout (arm)
            "dists/stable/main/binary-iphoneos-arm/Packages",
            "dists/stable/main/binary-iphoneos-arm/Packages.gz",
            "dists/stable/main/binary-iphoneos-arm/Packages.bz2",
            "dists/stable/main/binary-iphoneos-arm/Packages.xz",
            // Other dist variations
            "dists/./main/binary-iphoneos-arm/Packages",
            "dists/./main/binary-iphoneos-arm/Packages.gz",
            "dists/./main/binary-iphoneos-arm64/Packages",
            "dists/./main/binary-iphoneos-arm64/Packages.gz",
        ]

        var allPackages: [Package] = []
        var seenIDs: Set<String> = [] // bundleID+version+arch dedup

        for path in paths {
            guard let url = URL(string: baseURL + path) else { continue }
            do {
                let (data, response) = try await session.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else { continue }

                var textData = data

                // Decompress if needed
                if path.hasSuffix(".gz") {
                    if let decompressed = try? decompressGzip(data) {
                        textData = decompressed
                    } else { continue }
                } else if path.hasSuffix(".bz2") {
                    // bz2 not easily decompressable without library, skip
                    continue
                } else if path.hasSuffix(".xz") {
                    if let decompressed = try? decompressXZ(data) {
                        textData = decompressed
                    } else { continue }
                }

                guard let content = String(data: textData, encoding: .utf8) else { continue }
                let packages = parsePackagesFile(content: content, repoURL: baseURL)

                for pkg in packages {
                    let key = "\(pkg.bundleID)|\(pkg.version)|\(pkg.architecture)"
                    if !seenIDs.contains(key) {
                        seenIDs.insert(key)
                        allPackages.append(pkg)
                    }
                }

                // If we got packages from flat layout, likely no dists layout
                if !packages.isEmpty && !path.contains("dists") {
                    break
                }
            } catch { continue }
        }

        if allPackages.isEmpty {
            throw NetworkError.noPackagesFile
        }

        return allPackages
    }

    // MARK: - Download Deb
    func downloadDeb(package: Package, to directory: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        let baseURL = package.repoURL.hasSuffix("/") ? package.repoURL : package.repoURL + "/"
        let debURLString = package.filename.hasPrefix("http") ? package.filename : baseURL + package.filename

        guard let url = URL(string: debURLString) else { throw NetworkError.invalidURL }
        let (tempURL, response) = try await session.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { throw NetworkError.downloadFailed }

        let safe = { (s: String) in s.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_") }
        let fileName = "\(safe(package.bundleID))_\(safe(package.version))_\(package.archLabel).deb"
        let destURL = directory.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: destURL)
        return destURL
    }

    // MARK: - Parse Packages File
    private func parsePackagesFile(content: String, repoURL: String) -> [Package] {
        var packages: [Package] = []
        let entries = content.components(separatedBy: "\n\n")

        for entry in entries {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let fields = parseDebianFields(trimmed)
            guard let bundleID = fields["Package"], !bundleID.isEmpty else { continue }

            let pkg = Package(
                name: fields["Name"] ?? bundleID,
                bundleID: bundleID,
                version: fields["Version"] ?? "1.0",
                description: fields["Description"]?.components(separatedBy: "\n").first ?? "",
                author: fields["Author"] ?? fields["Maintainer"] ?? "",
                section: fields["Section"] ?? "Tweaks",
                size: fields["Size"] ?? "0",
                architecture: fields["Architecture"] ?? "iphoneos-arm",
                filename: fields["Filename"] ?? "",
                repoURL: repoURL,
                iconURL: fields["Icon"],
                depiction: fields["Depiction"] ?? fields["SileoDepiction"]
            )
            packages.append(pkg)
        }
        return packages
    }

    func parseDebianFields(_ text: String) -> [String: String] {
        var fields: [String: String] = [:]
        var key = "", val = ""
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                val += "\n" + line.trimmingCharacters(in: .whitespaces)
            } else if let c = line.firstIndex(of: ":") {
                if !key.isEmpty { fields[key] = val.trimmingCharacters(in: .whitespaces) }
                key = String(line[..<c]).trimmingCharacters(in: .whitespaces)
                val = String(line[line.index(after: c)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        if !key.isEmpty { fields[key] = val.trimmingCharacters(in: .whitespaces) }
        return fields
    }

    // MARK: - Decompression
    private func decompressGzip(_ data: Data) throws -> Data {
        guard data.count >= 18, data[0] == 0x1f, data[1] == 0x8b else {
            throw NetworkError.parsingError
        }
        var pos = 10
        let flg = data[3]
        if flg & 0x04 != 0 { pos += 2 + Int(data[pos]) + (Int(data[pos+1]) << 8) }
        if flg & 0x08 != 0 { while pos < data.count && data[pos] != 0 { pos += 1 }; pos += 1 }
        if flg & 0x10 != 0 { while pos < data.count && data[pos] != 0 { pos += 1 }; pos += 1 }
        if flg & 0x02 != 0 { pos += 2 }
        guard pos < data.count - 8 else { throw NetworkError.parsingError }

        let origSize = Int(data[data.count-4]) | Int(data[data.count-3])<<8 |
                       Int(data[data.count-2])<<16 | Int(data[data.count-1])<<24
        let raw = Data(data[pos..<(data.count - 8)])
        let bufSize = max(origSize, raw.count * 4, 1024 * 1024)

        // Try raw deflate first (iOS), then zlib-wrapped (macOS)
        if let r = decompress(raw, algo: COMPRESSION_ZLIB, bufSize: bufSize) { return r }
        var zw = Data([0x78, 0x9C]); zw.append(raw); zw.append(contentsOf: [0,0,0,0])
        if let r = decompress(zw, algo: COMPRESSION_ZLIB, bufSize: bufSize) { return r }
        throw NetworkError.parsingError
    }

    private func decompressXZ(_ data: Data) throws -> Data {
        if let r = decompress(data, algo: COMPRESSION_LZMA, bufSize: data.count * 10) { return r }
        throw NetworkError.parsingError
    }

    private func decompress(_ data: Data, algo: compression_algorithm, bufSize: Int) -> Data? {
        let sz = max(bufSize, 1024 * 1024)
        var out = Data(count: sz)
        let n = out.withUnsafeMutableBytes { d in
            data.withUnsafeBytes { s in
                compression_decode_buffer(
                    d.bindMemory(to: UInt8.self).baseAddress!, sz,
                    s.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, algo)
            }
        }
        guard n > 0 else { return nil }
        out.count = n
        return out
    }
}

enum NetworkError: LocalizedError {
    case invalidURL, serverError, downloadFailed, noPackagesFile, parsingError
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .serverError: return "Server error"
        case .downloadFailed: return "Download failed"
        case .noPackagesFile: return "No packages file found"
        case .parsingError: return "Failed to parse data"
        }
    }
}
