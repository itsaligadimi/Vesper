import CoreGraphics
import Foundation

struct Catalog: Codable, Equatable {
    var version: Int
    var name: String
    var generatedAt: String
    var about: String?
    var categories: [WallpaperCategory]
    var wallpapers: [Wallpaper]
}

struct WallpaperCategory: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var blurb: String
}

struct Wallpaper: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var title: String
    var category: String
    var location: String
    var author: String
    var license: String
    var licenseUrl: String
    var sourceUrl: String
    var motion: String
    var width: Int
    var height: Int
    var videoWidth: Int
    var videoHeight: Int
    var duration: Double
    var tags: [String]
    var featured: Bool
    var hero: Bool
    var thumbnail: String
    var image: String
    var video: String

    var motionLabel: String {
        switch motion {
        case "footage": return "Footage"
        case "original": return "Original"
        default: return "Camera drift"
        }
    }

    var resolutionLabel: String {
        "\(width)×\(height) still · \(videoWidth)×\(videoHeight) loop"
    }
}

struct ImportedClip: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var title: String
    var videoPath: String
    var stillPath: String
    var thumbPath: String
    var addedAt: Date
}

struct CatalogSourceFile: Codable {
    var repository: String
    var branch: String
}

enum SidebarItem: Hashable {
    case home
    case explore
    case favorites
    case imports
    case category(String)
}

enum DisplayTarget: Hashable {
    case all
    case display(CGDirectDisplayID)
}

enum CatalogError: LocalizedError {
    case unreadable
    case missing(String)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "The catalog manifest could not be read."
        case .missing(let path):
            return "Missing catalog file \(path)."
        }
    }
}

enum MoodSearch {
    /// Local word lists. No network, no model. A query like "calm" also matches mist, lake, and dunes.
    static let synonyms: [String: [String]] = [
        "calm": ["calm", "mist", "fog", "lake", "minimal", "quiet", "still"],
        "cozy": ["cozy", "autumn", "warm", "gold", "path"],
        "night": ["night", "stars", "aurora", "city", "lights", "milky"],
        "dramatic": ["dramatic", "storm", "volcano", "alpenglow", "lava", "rain"],
        "space": ["space", "nebula", "orbit", "stars", "cosmos", "earth", "aurora"],
        "ocean": ["ocean", "waves", "coast", "beach", "water", "shore"],
        "cold": ["snow", "winter", "cold", "white"],
        "warm": ["warm", "gold", "sand", "dune", "autumn", "alpenglow"],
        "green": ["green", "forest", "trees", "terraces"],
        "city": ["city", "skyline", "night", "lights", "harbour"],
        "anime": ["anime", "morevna", "castle", "cartoon"],
        "fantasy": ["fantasy", "dragon", "sintel", "magic", "forest"],
    ]

    static func matches(_ wallpaper: Wallpaper, query: String) -> Bool {
        let terms = query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
        if terms.isEmpty { return true }
        let haystack = ([wallpaper.title, wallpaper.location, wallpaper.author, wallpaper.category, wallpaper.motion] + wallpaper.tags)
            .joined(separator: " ")
            .lowercased()
        return terms.allSatisfy { term in
            if haystack.contains(term) { return true }
            let expanded = synonyms[term] ?? []
            return expanded.contains { haystack.contains($0) }
        }
    }
}

enum RepositoryParser {
    /// Accepts `owner/name` or a github.com URL.
    static func parse(_ raw: String) -> (owner: String, name: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("github.com"), let url = URL(string: trimmed) {
            let parts = url.path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
            guard parts.count >= 2 else { return nil }
            return (parts[0], parts[1].replacingOccurrences(of: ".git", with: ""))
        }
        let parts = trimmed.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1].replacingOccurrences(of: ".git", with: ""))
    }

    static func catalogBase(owner: String, name: String, branch: String) -> URL? {
        let safeBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "main" : branch
        let encodedBranch = safeBranch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? safeBranch
        return URL(string: "https://raw.githubusercontent.com/\(owner)/\(name)/\(encodedBranch)/catalog")
    }
}
