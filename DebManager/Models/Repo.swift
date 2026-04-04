import Foundation

struct Repo: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var url: String
    var iconURL: String?
    var repoDescription: String?
    var packageCount: Int
    var isDefault: Bool

    var displayName: String {
        if !name.isEmpty && name != url && !name.contains("://") {
            return name
        }
        return URL(string: url)?.host ?? url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
