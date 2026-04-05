import Foundation
import Compression

class DebConverter {
    static let shared = DebConverter()
    private let fm = FileManager.default
    private init() {}

    func convertBatch(packages: [(url: URL, from: ArchType, to: ArchType)], outputDirectory: URL,
                      progress: @escaping (Int, Int, String) -> Void) async -> [(url: URL?, error: String?)] {
        var results: [(url: URL?, error: String?)] = []
        for (i, pkg) in packages.enumerated() {
            progress(i, packages.count, pkg.url.lastPathComponent)
            do {
                let out = try await convert(debAt: pkg.url, from: pkg.from, to: pkg.to, outputDirectory: outputDirectory)
                results.append((out, nil))
            } catch { results.append((nil, error.localizedDescription)) }
        }
        return results
    }

    func convert(debAt sourceURL: URL, from sourceArch: ArchType, to targetArch: ArchType, outputDirectory: URL) async throws -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: sourceArch.archString, with: "")
            .replacingOccurrences(of: sourceArch.rawValue, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_- "))
        let outURL = outputDirectory.appendingPathComponent(
            "\(baseName.isEmpty ? "converted" : baseName)_\(targetArch.archString).deb"
        )

        // Try dpkg-deb first (jailbroken devices or injected binaries)
        if let dpkg = findBin("dpkg-deb") {
            let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let ext = tmp.appendingPathComponent("pkg")
            try fm.createDirectory(at: ext, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: tmp) }

            if spawn(dpkg, ["-R", sourceURL.path, ext.path]) {
                let deb = ext.appendingPathComponent("DEBIAN")
                chmodP(deb, r: true, m: "755")
                chmodP(deb.appendingPathComponent("control"), r: false, m: "644")
                try performDiskPathMapping(in: ext, from: sourceArch, to: targetArch)
                try updateControl(at: deb.appendingPathComponent("control"), to: targetArch)
                try updateScripts(in: deb, from: sourceArch, to: targetArch)
                signBins(in: ext); cleanDS(in: ext)
                for c in ["-Zzstd", "-Zgzip", ""] {
                    let a = c.isEmpty ? ["-b", ext.path, outURL.path] : [c, "-b", ext.path, outURL.path]
                    if spawn(dpkg, a) && fm.fileExists(atPath: outURL.path) { return outURL }
                }
            }
        }

        // Pure Swift: modify tar headers in-memory (no extraction, no repacking from scratch)
        return try inMemoryConvert(source: sourceURL, from: sourceArch, to: targetArch, outURL: outURL)
    }

    // MARK: - In-Memory Conversion
    private func inMemoryConvert(source: URL, from: ArchType, to: ArchType, outURL: URL) throws -> URL {
        let debData = try Data(contentsOf: source)
        let arEntries = try parseAr(data: debData)

        var debBin = Data("2.0\n".utf8)
        var ctrlCompressed: (name: String, data: Data)?
        var dataCompressed: (name: String, data: Data)?

        for e in arEntries {
            if e.name.hasPrefix("debian-binary") { debBin = e.data }
            else if e.name.hasPrefix("control.tar") { ctrlCompressed = (e.name, e.data) }
            else if e.name.hasPrefix("data.tar") { dataCompressed = (e.name, e.data) }
        }

        guard let ctrl = ctrlCompressed, let data = dataCompressed else {
            throw ConversionError.invalidDeb
        }

        // Modify control tar (change Architecture field)
        let ctrlTar = try decompress(ctrl.data, ctrl.name)
        let newCtrlTar = modifyFieldInTar(tarData: ctrlTar, file: "control",
                                          field: "Architecture", value: to.archString)
        let newCtrlGz = makeStoredGzip(newCtrlTar)

        // Try to decompress and modify data tar for path remapping
        let needsPathRemap = (from == .rootful && to != .rootful) || (from != .rootful && to == .rootful)
        var finalDataName = data.name
        var finalDataContent = data.data

        if needsPathRemap, let dataTar = try? decompress(data.data, data.name), isValidTar(dataTar) {
            let newDataTar = remapPathsInTar(tarData: dataTar, from: from, to: to)
            finalDataContent = makeStoredGzip(newDataTar)
            finalDataName = "data.tar.gz"
        }

        let newDeb = createAr(entries: [
            ("debian-binary", debBin),
            ("control.tar.gz", newCtrlGz),
            (finalDataName, finalDataContent)
        ])
        try newDeb.write(to: outURL)
        return outURL
    }

    private func isValidTar(_ data: Data) -> Bool {
        guard data.count >= 512 else { return false }
        if data.count > 262 {
            let magic = String(data: data[257..<262], encoding: .ascii)
            if magic == "ustar" { return true }
        }
        let firstByte = data[0]
        return firstByte == 0x2E || firstByte == 0x2F || (firstByte >= 0x30 && firstByte <= 0x7A)
    }

    private func remapPathsInTar(tarData: Data, from: ArchType, to: ArchType) -> Data {
        guard from != to else { return tarData }
        guard from == .rootful || to == .rootful else { return tarData }

        var result = Data(tarData)
        var off = 0

        while off + 512 <= result.count {
            if result[off..<off+512].allSatisfy({ $0 == 0 }) { break }
            let currentPath = readTarPath(from: result, at: off)
            let szStr = readField(from: result, at: off + 124, length: 12)
            let size = Int(szStr, radix: 8) ?? 0
            let type = result[off + 156]
            let newPath = mapPath(currentPath, from: from, to: to)

            if newPath != currentPath {
                writeTarPath(newPath, into: &result, at: off)
                if type == UInt8(ascii: "2") {
                    let linkTarget = readField(from: result, at: off + 157, length: 100)
                    let newLink = mapLinkTarget(linkTarget, from: from, to: to)
                    if newLink != linkTarget {
                        writeField(newLink, into: &result, at: off + 157, length: 100)
                    }
                }
                recalcChecksum(&result, at: off)
            } else if type == UInt8(ascii: "2") {
                let linkTarget = readField(from: result, at: off + 157, length: 100)
                let newLink = mapLinkTarget(linkTarget, from: from, to: to)
                if newLink != linkTarget {
                    writeField(newLink, into: &result, at: off + 157, length: 100)
                    recalcChecksum(&result, at: off)
                }
            }
            off += 512
            if size > 0 { off += ((size + 511) / 512) * 512 }
        }
        return result
    }

    private func mapPath(_ path: String, from: ArchType, to: ArchType) -> String {
        var p = path
        var prefix = ""
        if p.hasPrefix("./") { prefix = "./"; p = String(p.dropFirst(2)) }

        if from == .rootful && (to == .rootless || to == .roothide) {
            if p.hasPrefix("Library/MobileSubstrate/DynamicLibraries/") {
                let remainder = String(p.dropFirst("Library/MobileSubstrate/DynamicLibraries/".count))
                return prefix + "var/jb/usr/lib/TweakInject/" + remainder
            }
            if p == "Library/MobileSubstrate/DynamicLibraries" {
                return prefix + "var/jb/usr/lib/TweakInject"
            }
            if p == "Library/MobileSubstrate/" || p == "Library/MobileSubstrate" {
                return prefix + "var/jb/Library/MobileSubstrate"
            }
            let sysDirs = ["Library/", "usr/", "etc/", "Applications/", "System/", "bin/", "sbin/",
                           "Library", "usr", "etc", "Applications", "System", "bin", "sbin"]
            for sd in sysDirs {
                if p == sd || p.hasPrefix(sd) {
                    return prefix + "var/jb/" + p
                }
            }
        } else if (from == .rootless || from == .roothide) && to == .rootful {
            guard p.hasPrefix("var/jb/") else { return path }
            let stripped = String(p.dropFirst("var/jb/".count))
            if stripped.hasPrefix("usr/lib/TweakInject/") {
                let remainder = String(stripped.dropFirst("usr/lib/TweakInject/".count))
                return prefix + "Library/MobileSubstrate/DynamicLibraries/" + remainder
            }
            if stripped == "usr/lib/TweakInject" {
                return prefix + "Library/MobileSubstrate/DynamicLibraries"
            }
            return prefix + stripped
        }
        return path
    }

    private func mapLinkTarget(_ target: String, from: ArchType, to: ArchType) -> String {
        guard target.hasPrefix("/") else { return target }
        if from == .rootful && (to == .rootless || to == .roothide) {
            if !target.hasPrefix("/var/jb") {
                return "/var/jb" + target
            }
        } else if (from == .rootless || from == .roothide) && to == .rootful {
            if target.hasPrefix("/var/jb/") {
                return String(target.dropFirst("/var/jb".count))
            }
        }
        return target
    }

    private func readTarPath(from data: Data, at off: Int) -> String {
        let name = readField(from: data, at: off, length: 100)
        let prefix = readField(from: data, at: off + 345, length: 155)
        if prefix.isEmpty { return name }
        return prefix + "/" + name
    }

    private func writeTarPath(_ path: String, into data: inout Data, at off: Int) {
        let bytes = Array(path.utf8)
        if bytes.count <= 100 {
            clearField(&data, at: off, length: 100)
            for i in 0..<bytes.count { data[off + i] = bytes[i] }
            clearField(&data, at: off + 345, length: 155)
        } else {
            var splitIdx = -1
            for i in stride(from: min(bytes.count - 1, 155), through: 1, by: -1) {
                if bytes[i] == UInt8(ascii: "/") {
                    let nameLen = bytes.count - i - 1
                    if nameLen <= 100 {
                        splitIdx = i
                        break
                    }
                }
            }
            if splitIdx > 0 {
                let prefixBytes = Array(bytes[0..<splitIdx])
                let nameBytes = Array(bytes[(splitIdx + 1)...])
                clearField(&data, at: off, length: 100)
                for i in 0..<min(nameBytes.count, 100) { data[off + i] = nameBytes[i] }
                clearField(&data, at: off + 345, length: 155)
                for i in 0..<min(prefixBytes.count, 155) { data[off + 345 + i] = prefixBytes[i] }
            } else {
                clearField(&data, at: off, length: 100)
                for i in 0..<min(bytes.count, 100) { data[off + i] = bytes[i] }
                clearField(&data, at: off + 345, length: 155)
            }
        }
    }

    private func readField(from data: Data, at off: Int, length: Int) -> String {
        guard off + length <= data.count else { return "" }
        let slice = data[off..<off+length]
        if let n = slice.firstIndex(of: 0) {
            return String(data: data[off..<n], encoding: .utf8)?.trimmingCharacters(in: .whitespaces) ?? ""
        }
        return String(data: slice, encoding: .utf8)?.trimmingCharacters(in: .init(charactersIn: "\0 ")) ?? ""
    }

    private func writeField(_ value: String, into data: inout Data, at off: Int, length: Int) {
        clearField(&data, at: off, length: length)
        let bytes = Array(value.utf8)
        for i in 0..<min(bytes.count, length) { data[off + i] = bytes[i] }
    }

    private func clearField(_ data: inout Data, at off: Int, length: Int) {
        for i in 0..<length { data[off + i] = 0 }
    }

    private func recalcChecksum(_ data: inout Data, at off: Int) {
        for i in 148..<156 { data[off + i] = 0x20 }
        var sum = 0
        for i in 0..<512 { sum += Int(data[off + i]) }
        let ckStr = String(sum, radix: 8)
        let padded = String(repeating: "0", count: max(0, 6 - ckStr.count)) + ckStr
        for (i, c) in padded.utf8.enumerated() where i < 6 { data[off + 148 + i] = c }
        data[off + 154] = 0
        data[off + 155] = 0x20
    }

    private func modifyFieldInTar(tarData: Data, file: String, field: String, value: String) -> Data {
        var result = Data(tarData)
        var off = 0
        while off + 512 <= result.count {
            if result[off..<off+512].allSatisfy({ $0 == 0 }) { break }
            let path = readTarPath(from: result, at: off)
            let cleanPath = path.replacingOccurrences(of: "./", with: "")
            let szStr = readField(from: result, at: off + 124, length: 12)
            let size = Int(szStr, radix: 8) ?? 0
            let type = result[off + 156]

            if (type == 0 || type == 0x30) && cleanPath == file && size > 0 {
                let dataStart = off + 512
                guard dataStart + size <= result.count,
                      var content = String(data: result[dataStart..<dataStart+size], encoding: .utf8) else { break }

                content = replaceField(in: content, field: field, value: value)
                let newData = Data(content.utf8)
                let newSize = newData.count
                let sizeStr = String(newSize, radix: 8)
                let paddedSize = String(repeating: "0", count: max(0, 11 - sizeStr.count)) + sizeStr
                for (i, c) in paddedSize.utf8.enumerated() where i < 11 { result[off + 124 + i] = c }
                result[off + 135] = 0
                recalcChecksum(&result, at: off)
                let oldPadded = ((size + 511) / 512) * 512
                let newPadded = ((newSize + 511) / 512) * 512
                var newContent = Data(newData)
                let pad = newPadded - newSize
                if pad > 0 { newContent.append(Data(repeating: 0, count: pad)) }
                let before = result[0..<dataStart]
                let after = (dataStart + oldPadded < result.count) ? result[(dataStart + oldPadded)...] : Data()
                result = Data(); result.append(before); result.append(newContent); result.append(after)
                break
            }
            off += 512
            if size > 0 { off += ((size + 511) / 512) * 512 }
        }
        return result
    }

    private func performDiskPathMapping(in dir: URL, from: ArchType, to: ArchType) throws {
        switch (from, to) {
        case (.rootful, .rootless), (.rootful, .roothide):
            let jb = dir.appendingPathComponent("var/jb")
            try fm.createDirectory(at: jb, withIntermediateDirectories: true)
            let ms = dir.appendingPathComponent("Library/MobileSubstrate/DynamicLibraries")
            if fm.fileExists(atPath: ms.path) {
                let ti = jb.appendingPathComponent("usr/lib/TweakInject")
                try fm.createDirectory(at: ti.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: ms, to: ti)
                let p = dir.appendingPathComponent("Library/MobileSubstrate")
                if isDirEmpty(p) { try? fm.removeItem(at: p) }
            }
            for d in ["Library","usr","etc","Applications","System","bin","sbin"] {
                let s = dir.appendingPathComponent(d)
                guard fm.fileExists(atPath: s.path) else { continue }
                let dst = jb.appendingPathComponent(d)
                if fm.fileExists(atPath: dst.path) { try mergeDir(s, dst); try? fm.removeItem(at: s) }
                else { try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true); try fm.moveItem(at: s, to: dst) }
            }
        case (.rootless, .rootful), (.roothide, .rootful):
            let jb = dir.appendingPathComponent("var/jb")
            guard fm.fileExists(atPath: jb.path) else { break }
            let ti = jb.appendingPathComponent("usr/lib/TweakInject")
            if fm.fileExists(atPath: ti.path) {
                let ms = dir.appendingPathComponent("Library/MobileSubstrate/DynamicLibraries")
                try fm.createDirectory(at: ms.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: ti, to: ms)
            }
            for item in try fm.contentsOfDirectory(at: jb, includingPropertiesForKeys: nil) {
                let dst = dir.appendingPathComponent(item.lastPathComponent)
                if fm.fileExists(atPath: dst.path) { try mergeDir(item, dst); try? fm.removeItem(at: item) }
                else { try fm.moveItem(at: item, to: dst) }
            }
            try? fm.removeItem(at: jb)
            if isDirEmpty(dir.appendingPathComponent("var")) { try? fm.removeItem(at: dir.appendingPathComponent("var")) }
        default: break
        }
    }

    private func makeStoredGzip(_ input: Data) -> Data {
        var gz = Data([0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF])
        var off = 0
        while off < input.count {
            let bs = min(input.count - off, 65535)
            gz.append(off + bs >= input.count ? 0x01 : 0x00)
            let len = UInt16(bs); gz.append(UInt8(len & 0xFF)); gz.append(UInt8(len >> 8))
            let nlen = ~len; gz.append(UInt8(nlen & 0xFF)); gz.append(UInt8(nlen >> 8))
            gz.append(input[off..<off+bs]); off += bs
        }
        if input.isEmpty { gz.append(contentsOf: [0x01, 0x00, 0x00, 0xFF, 0xFF]) }
        let crc = crc32(input)
        for s: UInt32 in [0,8,16,24] { gz.append(UInt8(truncatingIfNeeded: crc >> s)) }
        let sz = UInt32(truncatingIfNeeded: input.count)
        for s: UInt32 in [0,8,16,24] { gz.append(UInt8(truncatingIfNeeded: sz >> s)) }
        return gz
    }

    private func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in data { c ^= UInt32(b); for _ in 0..<8 { c = (c >> 1) ^ (c & 1 != 0 ? 0xEDB88320 : 0) } }
        return c ^ 0xFFFFFFFF
    }

    private struct ArEntry { let name: String; let data: Data }
    private func parseAr(data: Data) throws -> [ArEntry] {
        guard data.count > 8, String(data: data[0..<8], encoding: .ascii) == "!<arch>\n" else { throw ConversionError.invalidDeb }
        var entries: [ArEntry] = []; var off = 8
        while off + 60 <= data.count {
            let nm = String(data: data[off..<off+16], encoding: .ascii)?.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "") ?? ""
            let sz = Int(String(data: data[off+48..<off+58], encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "0") ?? 0
            off += 60; guard !nm.isEmpty, off + sz <= data.count else { break }
            entries.append(ArEntry(name: nm, data: Data(data[off..<off+sz]))); off += sz; if off % 2 != 0 { off += 1 }
        }
        return entries
    }

    private func createAr(entries: [(String, Data)]) -> Data {
        var out = Data("!<arch>\n".utf8); let ts = String(Int(Date().timeIntervalSince1970))
        for (name, data) in entries {
            let h = (name + "/").padding(toLength: 16, withPad: " ", startingAt: 0)
                + ts.padding(toLength: 12, withPad: " ", startingAt: 0)
                + "0".padding(toLength: 6, withPad: " ", startingAt: 0) + "0".padding(toLength: 6, withPad: " ", startingAt: 0)
                + "100644".padding(toLength: 8, withPad: " ", startingAt: 0)
                + String(data.count).padding(toLength: 10, withPad: " ", startingAt: 0) + "`\n"
            out.append(Data(h.utf8)); out.append(data); if data.count % 2 != 0 { out.append(0x0A) }
        }
        return out
    }

    private func decompress(_ data: Data, _ name: String) throws -> Data {
        if data.count >= 2 && data[0] == 0x1f && data[1] == 0x8b { return try gunzip(data) }
        if name.hasSuffix(".xz") || (data.count >= 6 && data[0] == 0xFD) { return try decBuf(data, COMPRESSION_LZMA, data.count*10) }
        if name.hasSuffix(".zst") || isZstd(data) { return try zstdDecompress(data) }
        return data
    }

    private func isZstd(_ data: Data) -> Bool {
        data.count >= 4 && data[0] == 0x28 && data[1] == 0xB5 && data[2] == 0x2F && data[3] == 0xFD
    }

    private func zstdDecompress(_ data: Data) throws -> Data {
        guard let zstd = findBin("zstd") else {
            throw ConversionError.conversionFailed("zstd not supported without helper binary")
        }

        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let input = tmp.appendingPathComponent("input.zst")
        let output = tmp.appendingPathComponent("output.tar")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        try data.write(to: input)
        guard spawn(zstd, ["-q", "-d", "-f", input.path, "-o", output.path]),
              fm.fileExists(atPath: output.path) else {
            throw ConversionError.conversionFailed("zstd decompression failed")
        }
        return try Data(contentsOf: output)
    }

    private func gunzip(_ data: Data) throws -> Data {
        guard data.count >= 18, data[0] == 0x1f, data[1] == 0x8b else { throw ConversionError.conversionFailed("Not gzip") }
        var p = 10; let fl = data[3]
        if fl & 0x04 != 0 { p += 2 + Int(data[p]) + (Int(data[p+1]) << 8) }
        if fl & 0x08 != 0 { while p < data.count && data[p] != 0 { p += 1 }; p += 1 }
        if fl & 0x10 != 0 { while p < data.count && data[p] != 0 { p += 1 }; p += 1 }
        if fl & 0x02 != 0 { p += 2 }
        guard p < data.count - 8 else { throw ConversionError.conversionFailed("Bad gzip") }
        let origSz = Int(data[data.count-4]) | Int(data[data.count-3])<<8 | Int(data[data.count-2])<<16 | Int(data[data.count-1])<<24
        let raw = Data(data[p..<(data.count - 8)])
        if let r = try? decBuf(raw, COMPRESSION_ZLIB, max(origSz, raw.count*4, 1<<20)) { return r }
        var zw = Data([0x78, 0x9C]); zw.append(raw); zw.append(contentsOf: [0,0,0,0])
        return try decBuf(zw, COMPRESSION_ZLIB, max(origSz, raw.count*4, 1<<20))
    }

    private func decBuf(_ data: Data, _ algo: compression_algorithm, _ bufSz: Int) throws -> Data {
        let sz = max(bufSz, 1<<20); var out = Data(count: sz)
        let n = out.withUnsafeMutableBytes { d in data.withUnsafeBytes { s in
            compression_decode_buffer(d.bindMemory(to: UInt8.self).baseAddress!, sz,
                s.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, algo) } }
        guard n > 0 else { throw ConversionError.conversionFailed("Decompress failed") }
        out.count = n; return out
    }

    private func findBin(_ name: String) -> String? {
        // 优先在 App 内部 Bundle 路径查找注入的二进制工具
        let bundlePath = Bundle.main.bundlePath + "/\(name)"
        
        var paths = [
            bundlePath,
            "/var/jb/usr/bin/\(name)",
            "/usr/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/opt/procursus/usr/bin/\(name)",
            "/var/jb/bin/\(name)"
        ]

        if let resolved = try? fm.destinationOfSymbolicLink(atPath: "/var/jb") {
            paths.insert(resolved + "/usr/bin/\(name)", at: 0)
            paths.insert(resolved + "/bin/\(name)", at: 1)
        }

        for path in paths {
            ensureExecutable(path)
            if canSpawn(path) {
                return path
            }
        }
        return nil
    }

    private func canSpawn(_ path: String) -> Bool {
        var pid: pid_t = 0
        let cPath = strdup(path)!
        defer { free(cPath) }
        let cArgs: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
        let cE: [UnsafeMutablePointer<CChar>?] = makeEnv(for: path).map { strdup($0) } + [nil]
        defer { cE.forEach { $0.flatMap { free($0) } } }
        let ret = posix_spawn(&pid, path, nil, nil, cArgs, cE)
        if ret == 0 {
            var st: Int32 = 0
            kill(pid, SIGKILL)
            waitpid(pid, &st, 0)
            return true
        }
        return false
    }

    private func trySpawn(_ path: String, _ args: [String]) -> Bool {
        var pid: pid_t = 0
        let all = [path] + args
        let cA: [UnsafeMutablePointer<CChar>?] = all.map { strdup($0) } + [nil]
        defer { cA.forEach { $0.flatMap { free($0) } } }
        let cE: [UnsafeMutablePointer<CChar>?] = makeEnv(for: path).map { strdup($0) } + [nil]
        defer { cE.forEach { $0.flatMap { free($0) } } }
        let ret = posix_spawn(&pid, path, nil, nil, cA, cE)
        if ret == 0 {
            var st: Int32 = 0
            waitpid(pid, &st, 0)
            return true
        }
        return false
    }

    @discardableResult private func spawn(_ path: String, _ args: [String]) -> Bool {
        var pid: pid_t = 0; let all = [path] + args
        let cA: [UnsafeMutablePointer<CChar>?] = all.map { strdup($0) } + [nil]
        defer { cA.forEach { $0.flatMap { free($0) } } }
        let cE: [UnsafeMutablePointer<CChar>?] = makeEnv(for: path).map { strdup($0) } + [nil]
        defer { cE.forEach { $0.flatMap { free($0) } } }
        guard posix_spawn(&pid, path, nil, nil, cA, cE) == 0 else { return false }
        var st: Int32 = 0; waitpid(pid, &st, 0); return (st & 0x7f) == 0 && ((st >> 8) & 0xff) == 0
    }

    private func makeEnv(for executablePath: String) -> [String] {
        let env = ProcessInfo.processInfo.environment
        let bundlePath = Bundle.main.bundlePath
        let execDir = URL(fileURLWithPath: executablePath).deletingLastPathComponent().path
        let useBundleRuntime = executablePath.hasPrefix(bundlePath)
        let pathSeed = [
            useBundleRuntime ? bundlePath : nil,
            execDir,
            env["PATH"],
            "/usr/bin:/var/jb/usr/bin:/bin:/sbin"
        ]
        let pathParts = pathSeed.compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        var result = [
            "PATH=\(pathParts.joined(separator: ":"))",
            "TMPDIR=\(fm.temporaryDirectory.path)"
        ]
        if useBundleRuntime {
            let librarySeed = [
                bundlePath,
                execDir,
                env["DYLD_LIBRARY_PATH"],
                env["DYLD_FALLBACK_LIBRARY_PATH"]
            ]
            let libraryParts = librarySeed.compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            if !libraryParts.isEmpty {
                let libPath = libraryParts.joined(separator: ":")
                result.append("DYLD_LIBRARY_PATH=\(libPath)")
                result.append("DYLD_FALLBACK_LIBRARY_PATH=\(libPath)")
            }
        }
        if let home = env["HOME"], !home.isEmpty { result.append("HOME=\(home)") }
        return result
    }

    private func ensureExecutable(_ path: String) {
        guard path.hasPrefix(Bundle.main.bundlePath), fm.fileExists(atPath: path) else { return }
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    }

    private func chmodP(_ u: URL, r: Bool, m: String) {
        for b in ["/bin/chmod","/usr/bin/chmod","/var/jb/usr/bin/chmod"] {
            if spawn(b, r ? ["-R",m,u.path] : [m,u.path]) { return } } }

    private func signBins(in dir: URL) {
        guard let ldid = findBin("ldid"), let e = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { return }
        for case let u as URL in e {
            if u.path.contains("/DEBIAN/") { continue }
            guard let d = try? Data(contentsOf: u, options: .mappedIfSafe), d.count >= 4 else { continue }
            let m = d.withUnsafeBytes { $0.load(as: UInt32.self) }
            if m == 0xFEEDFACF || m == 0xFEEDFACE || m == 0xBEBAFECA || m == 0xCFFAEDFE || m == 0xCEFAEDFE {
                spawn(ldid, ["-S", u.path]) } } }

    private func updateControl(at p: URL, to: ArchType) throws {
        guard var c = try? String(contentsOf: p, encoding: .utf8) else { return }
        c = replaceField(in: c, field: "Architecture", value: to.archString)
        let lines = c.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        try (lines.joined(separator: "\n") + "\n").write(to: p, atomically: true, encoding: .utf8)
    }

    private func updateScripts(in deb: URL, from: ArchType, to: ArchType) throws {
        for s in ["preinst","postinst","prerm","postrm","extrainst_"] {
            let f = deb.appendingPathComponent(s)
            guard fm.fileExists(atPath: f.path), var c = try? String(contentsOf: f, encoding: .utf8) else { continue }
            c = c.replacingOccurrences(of: from.archString, with: to.archString)
            if from == .rootful && (to == .rootless || to == .roothide) {
                c = c.replacingOccurrences(of: "/var/jb/", with: "/-vj/-"); c = c.replacingOccurrences(of: "/var/jb", with: "/-vj-")
                for p in ["/Applications/","/Library/","/private/","/System/","/sbin/","/bin/","/etc/","/usr/"] {
                    c = c.replacingOccurrences(of: " \(p)", with: " /var/jb\(p)") }
                c = c.replacingOccurrences(of: "/-vj/-", with: "/var/jb/"); c = c.replacingOccurrences(of: "/-vj-", with: "/var/jb")
                if c.hasPrefix("#!/var/jb/") { c = "#!/" + String(c.dropFirst("#!/var/jb/".count)) }
            } else if (from == .rootless || from == .roothide) && to == .rootful {
                c = c.replacingOccurrences(of: "/var/jb/", with: "/"); c = c.replacingOccurrences(of: "/var/jb", with: "") }
            try c.write(to: f, atomically: true, encoding: .utf8); chmodP(f, r: false, m: "755") } }

    private func mergeDir(_ s: URL, _ d: URL) throws {
        try fm.createDirectory(at: d, withIntermediateDirectories: true)
        for i in try fm.contentsOfDirectory(at: s, includingPropertiesForKeys: [.isDirectoryKey]) {
            let di = d.appendingPathComponent(i.lastPathComponent)
            if (try? i.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && fm.fileExists(atPath: di.path) {
                try mergeDir(i, di)
            } else { if fm.fileExists(atPath: di.path) { try fm.removeItem(at: di) }; try fm.moveItem(at: i, to: di) } } }

    private func isDirEmpty(_ u: URL) -> Bool { (try? fm.contentsOfDirectory(atPath: u.path))?.isEmpty ?? true }
    private func replaceField(in c: String, field: String, value: String) -> String {
        var l = c.components(separatedBy: "\n"); var f = false
        for i in 0..<l.count where l[i].hasPrefix("\(field):") { l[i] = "\(field): \(value)"; f = true; break }
        if !f { l.append("\(field): \(value)") }; return l.joined(separator: "\n") }
    private func cleanDS(in d: URL) {
        if let e = fm.enumerator(at: d, includingPropertiesForKeys: nil) {
            for case let u as URL in e where u.lastPathComponent == ".DS_Store" { try? fm.removeItem(at: u) } } }
}

enum ConversionError: LocalizedError {
    case invalidDeb, missingComponent(String), conversionFailed(String)
    var errorDescription: String? {
        switch self {
        case .invalidDeb: return "Invalid .deb file"
        case .missingComponent(let c): return "Missing: \(c)"
        case .conversionFailed(let r): return "Failed: \(r)" } }
}
