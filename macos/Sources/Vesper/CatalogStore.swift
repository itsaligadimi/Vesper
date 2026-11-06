import Foundation

@MainActor
final class CatalogStore: ObservableObject {
    @Published private(set) var catalog: Catalog?
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var sourceDescription = "Looking for the catalog"
    @Published private(set) var usingRemoteManifest = false

    private var localRoot: URL?
    private let cacheRoot: URL
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        cacheRoot = support.appendingPathComponent("Vesper/Cache", isDirectory: true)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        localRoot = Self.findLocalCatalog()
        if let localRoot,
           let sourceURL = optionalFile(localRoot.appendingPathComponent("source.json")),
           let data = try? Data(contentsOf: sourceURL),
           let source = try? JSONDecoder().decode(CatalogSourceFile.self, from: data) {
            settings.applySourceFile(source)
        }

        var loaded: Catalog?
        var remoteUsed = false
        if let remote = settings.remoteBase?.appendingPathComponent("manifest.json") {
            do {
                var request = URLRequest(url: remote, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
                request.setValue("Vesper/1.0", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                   let decoded = try? JSONDecoder().decode(Catalog.self, from: data) {
                    loaded = decoded
                    remoteUsed = true
                }
            } catch {
                // The bundled or cloned catalog still works offline.
            }
        }

        if loaded == nil, let localRoot {
            let manifest = localRoot.appendingPathComponent("manifest.json")
            do {
                let data = try Data(contentsOf: manifest)
                loaded = try JSONDecoder().decode(Catalog.self, from: data)
            } catch {
                errorMessage = "Could not read \(manifest.path). \(error.localizedDescription)"
            }
        }

        catalog = loaded
        usingRemoteManifest = remoteUsed
        if let localRoot, remoteUsed {
            sourceDescription = "GitHub catalog, with local files when they are already on disk"
        } else if remoteUsed {
            sourceDescription = "GitHub catalog"
        } else if localRoot != nil {
            sourceDescription = "Catalog on this Mac"
        } else {
            sourceDescription = "No catalog found"
            if errorMessage == nil {
                errorMessage = "Vesper could not find catalog/manifest.json next to the app, in this folder, or on GitHub. Set the repository in Settings, or run the app from a checkout of this project."
            }
        }
        isLoading = false
    }

    func category(for wallpaper: Wallpaper) -> WallpaperCategory? {
        catalog?.categories.first { $0.id == wallpaper.category }
    }

    func wallpaper(id: String) -> Wallpaper? {
        catalog?.wallpapers.first { $0.id == id }
    }

    /// A file URL when the asset is already on disk. Thumbnails prefer this path.
    func localFile(_ relative: String) -> URL? {
        if let localRoot {
            let url = localRoot.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        let cached = cacheRoot.appendingPathComponent(relative)
        if FileManager.default.fileExists(atPath: cached.path) { return cached }
        return nil
    }

    func displayURL(_ relative: String) -> URL? {
        if let local = localFile(relative) { return local }
        return settings.remoteBase?.appendingPathComponent(relative)
    }

    func ensureCached(_ relative: String) async throws -> URL {
        if let local = localFile(relative) { return local }
        guard let remote = settings.remoteBase?.appendingPathComponent(relative) else {
            throw CatalogError.missing(relative)
        }
        var request = URLRequest(url: remote, timeoutInterval: 120)
        request.setValue("Vesper/1.0", forHTTPHeaderField: "User-Agent")
        let (temporary, response) = try await URLSession.shared.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CatalogError.missing(relative)
        }
        let destination = cacheRoot.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    private func optionalFile(_ url: URL) -> URL? {
        FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func findLocalCatalog() -> URL? {
        var candidates: [URL] = []
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "--catalog"), flag + 1 < arguments.count {
            candidates.append(URL(fileURLWithPath: arguments[flag + 1]))
        }
        if let env = ProcessInfo.processInfo.environment["VESPER_CATALOG"], !env.isEmpty {
            candidates.append(URL(fileURLWithPath: env))
        }
        if let resource = Bundle.main.resourceURL?.appendingPathComponent("catalog") {
            candidates.append(resource)
        }
        var cursor = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<7 {
            candidates.append(cursor.appendingPathComponent("catalog"))
            cursor.deleteLastPathComponent()
        }
        if let executable = Bundle.main.executableURL?.deletingLastPathComponent() {
            var folder = executable
            for _ in 0..<8 {
                candidates.append(folder.appendingPathComponent("catalog"))
                folder.deleteLastPathComponent()
            }
        }
        for url in candidates {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("manifest.json").path) {
                return url
            }
        }
        return nil
    }
}
