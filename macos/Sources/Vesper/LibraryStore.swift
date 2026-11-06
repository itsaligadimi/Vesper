import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var favoriteIDs: Set<String> = []
    @Published private(set) var imports: [ImportedClip] = []

    private let support: URL
    private let importsDirectory: URL
    private let favoritesURL: URL
    private let importsURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vesper", isDirectory: true)
        support = base
        importsDirectory = base.appendingPathComponent("Imports", isDirectory: true)
        favoritesURL = base.appendingPathComponent("favorites.json")
        importsURL = base.appendingPathComponent("imports.json")
    }

    func load() {
        try? FileManager.default.createDirectory(at: importsDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: favoritesURL),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            favoriteIDs = Set(ids)
        }
        if let data = try? Data(contentsOf: importsURL),
           let clips = try? JSONDecoder().decode([ImportedClip].self, from: data) {
            imports = clips.filter { FileManager.default.fileExists(atPath: $0.videoPath) }
        }
    }

    func isFavorite(_ id: String) -> Bool {
        favoriteIDs.contains(id)
    }

    func toggleFavorite(_ id: String) {
        if favoriteIDs.contains(id) {
            favoriteIDs.remove(id)
        } else {
            favoriteIDs.insert(id)
        }
        persistFavorites()
    }

    func importFile(at url: URL) async throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let allowed: Set<String> = ["mp4", "mov", "m4v"]
        guard allowed.contains(url.pathExtension.lowercased()) else {
            throw CatalogError.missing("Choose an MP4, MOV, or M4V file.")
        }
        try FileManager.default.createDirectory(at: importsDirectory, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let videoDest = importsDirectory.appendingPathComponent("\(id).\(url.pathExtension.lowercased())")
        if FileManager.default.fileExists(atPath: videoDest.path) {
            try FileManager.default.removeItem(at: videoDest)
        }
        try FileManager.default.copyItem(at: url, to: videoDest)
        let still = importsDirectory.appendingPathComponent("\(id)-still.jpg")
        let thumb = importsDirectory.appendingPathComponent("\(id)-thumb.jpg")
        try await Self.writeFrames(from: videoDest, still: still, thumb: thumb)
        let title = url.deletingPathExtension().lastPathComponent
        let clip = ImportedClip(
            id: "import:\(id)",
            title: title,
            videoPath: videoDest.path,
            stillPath: still.path,
            thumbPath: thumb.path,
            addedAt: Date()
        )
        imports.insert(clip, at: 0)
        persistImports()
    }

    func clip(id: String) -> ImportedClip? {
        imports.first { $0.id == id }
    }

    private func persistFavorites() {
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let data = try? JSONEncoder().encode(Array(favoriteIDs).sorted())
        try? data?.write(to: favoritesURL, options: .atomic)
    }

    private func persistImports() {
        let data = try? JSONEncoder().encode(imports)
        try? data?.write(to: importsURL, options: .atomic)
    }

    private static func writeFrames(from video: URL, still: URL, thumb: URL) async throws {
        let asset = AVURLAsset(url: video)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1920, height: 1920)
        let duration = try await asset.load(.duration)
        let seconds = min(1.0, max(0.1, duration.seconds / 3))
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let (image, _) = try await generator.image(at: time)
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let full = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.86]) else {
            throw CatalogError.unreadable
        }
        try full.write(to: still)
        let thumbImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        let thumbSize = NSSize(width: 640, height: max(1, 640 * CGFloat(image.height) / CGFloat(image.width)))
        let rendered = NSImage(size: thumbSize)
        rendered.lockFocus()
        thumbImage.draw(in: NSRect(origin: .zero, size: thumbSize))
        rendered.unlockFocus()
        guard let tiff = rendered.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let small = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            try full.write(to: thumb)
            return
        }
        try small.write(to: thumb)
    }
}
