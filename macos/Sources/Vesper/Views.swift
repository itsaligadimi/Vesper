import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum Vesper {
    static let background = Color(red: 0.07, green: 0.07, blue: 0.075)
    static let sidebar = Color(red: 0.09, green: 0.09, blue: 0.098)
    static let card = Color.white.opacity(0.04)
    static let gold = Color(red: 0.89, green: 0.71, blue: 0.40)
    static let ink = Color(red: 0.94, green: 0.93, blue: 0.90)
    static let muted = Color.white.opacity(0.58)
}

struct RootView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var wallpaper: WallpaperController
    @State private var section: SidebarItem? = .home
    @State private var selected: Wallpaper?
    @State private var query = ""
    @State private var display: DisplayTarget = .all
    @State private var showSettings = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .background(Vesper.background)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(catalog)
                .environmentObject(settings)
                .frame(width: 520, height: 560)
        }
        .onAppear { armRotation() }
        .onChange(of: settings.rotationMinutes) { _, _ in armRotation() }
        .task {
            await catalog.load()
            library.load()
            wallpaper.restore()
            armRotation()
        }
    }

    private var sidebar: some View {
        List(selection: $section) {
            Section {
                Label("Home", systemImage: "square.grid.2x2").tag(SidebarItem.home)
                Label("Explore", systemImage: "sparkle.magnifyingglass").tag(SidebarItem.explore)
                Label("Favorites", systemImage: "heart").tag(SidebarItem.favorites)
                Label("Your Videos", systemImage: "film").tag(SidebarItem.imports)
            }
            if let categories = catalog.catalog?.categories {
                Section("Categories") {
                    ForEach(categories) { category in
                        Label(category.name, systemImage: symbol(for: category.id))
                            .tag(SidebarItem.category(category.id))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Vesper.ink)
                Text(catalog.sourceDescription)
                    .font(.caption)
                    .foregroundStyle(Vesper.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
        }
        .navigationTitle("Vesper")
        .frame(minWidth: 210)
    }

    @ViewBuilder
    private var detail: some View {
        if catalog.isLoading {
            ProgressView("Opening the library")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let message = catalog.errorMessage, catalog.catalog == nil {
            ContentUnavailableView("Catalog unavailable", systemImage: "externaldrive.badge.exclamationmark", description: Text(message))
        } else {
            ZStack(alignment: .trailing) {
                Group {
                    switch section ?? .home {
                    case .home:
                        HomeView(query: $query, selected: $selected)
                    case .explore:
                        GalleryView(title: "Explore", subtitle: "Search by place, color, or mood.", wallpapers: filtered(nil), query: $query, selected: $selected)
                    case .favorites:
                        GalleryView(title: "Favorites", subtitle: "Hearts stay on this Mac.", wallpapers: favorites, query: $query, selected: $selected, empty: "Heart a wallpaper and it will wait here.")
                    case .imports:
                        ImportsView()
                    case .category(let id):
                        GalleryView(
                            title: catalog.catalog?.categories.first { $0.id == id }?.name ?? "Category",
                            subtitle: catalog.catalog?.categories.first { $0.id == id }?.blurb ?? "",
                            wallpapers: filtered(id),
                            query: $query,
                            selected: $selected
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let selected {
                    PreviewPane(wallpaper: selected, display: $display, onClose: { self.selected = nil })
                        .frame(width: 380)
                        .background(Vesper.sidebar)
                        .overlay(alignment: .leading) { Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1) }
                }
            }
        }
    }

    private var favorites: [Wallpaper] {
        catalog.catalog?.wallpapers.filter { library.isFavorite($0.id) } ?? []
    }

    private func filtered(_ category: String?) -> [Wallpaper] {
        let all = catalog.catalog?.wallpapers ?? []
        return all.filter { wallpaper in
            let categoryOK = category == nil || wallpaper.category == category
            return categoryOK && MoodSearch.matches(wallpaper, query: query)
        }
    }

    private func armRotation() {
        wallpaper.configureRotation(minutes: settings.rotationMinutes) {
            let pool = favorites.isEmpty ? (catalog.catalog?.wallpapers ?? []) : favorites
            guard let pick = pool.randomElement(), let still = catalog.localFile(pick.image) else { return nil }
            return WallpaperController.Assignment(
                id: pick.id,
                title: pick.title,
                live: true,
                stillPath: still.path,
                videoPath: catalog.localFile(pick.video)?.path
            )
        }
    }

    private func symbol(for category: String) -> String {
        switch category {
        case "nature": return "leaf"
        case "ocean": return "water.waves"
        case "mountains": return "mountain.2"
        case "cosmos": return "sparkles"
        case "cities": return "building.2"
        case "aerial": return "binoculars"
        case "weather": return "cloud.sun"
        case "minimal": return "circle.lefthalf.filled"
        case "abstract": return "paintpalette"
        default: return "photo"
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @Binding var query: String
    @Binding var selected: Wallpaper?

    var body: some View {
        let wallpapers = catalog.catalog?.wallpapers ?? []
        let hero = wallpapers.first { $0.hero } ?? wallpapers.first { $0.featured } ?? wallpapers.first
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if let hero {
                    HeroCard(wallpaper: hero) { selected = hero }
                }
                if let categories = catalog.catalog?.categories {
                    ForEach(categories) { category in
                        let items = wallpapers.filter { $0.category == category.id && MoodSearch.matches($0, query: query) }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(category.name).font(.title3.weight(.semibold))
                                    Spacer()
                                    Text(category.blurb).font(.callout).foregroundStyle(Vesper.muted).lineLimit(1)
                                }
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 14) {
                                        ForEach(items) { wallpaper in
                                            WallpaperCard(wallpaper: wallpaper)
                                                .frame(width: 280)
                                                .onTapGesture { selected = wallpaper }
                                        }
                                    }
                                    .padding(.bottom, 4)
                                }
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
        .background(Vesper.background)
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Evening, on your desktop")
                    .font(.system(size: 32, weight: .medium, design: .serif))
                    .foregroundStyle(Vesper.ink)
                Text("Thumbnails first. The loop downloads only when you preview or apply it.")
                    .foregroundStyle(Vesper.muted)
            }
            Spacer()
            SearchField(text: $query)
                .frame(width: 260)
        }
    }
}

struct GalleryView: View {
    var title: String
    var subtitle: String
    var wallpapers: [Wallpaper]
    @Binding var query: String
    @Binding var selected: Wallpaper?
    var empty: String = "Nothing matches that search."

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 340), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.system(size: 28, weight: .medium, design: .serif))
                        Text(subtitle).foregroundStyle(Vesper.muted)
                    }
                    Spacer()
                    SearchField(text: $query).frame(width: 260)
                }
                if wallpapers.isEmpty {
                    ContentUnavailableView(title, systemImage: "rectangle.dashed", description: Text(empty))
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(wallpapers) { wallpaper in
                            WallpaperCard(wallpaper: wallpaper)
                                .onTapGesture { selected = wallpaper }
                        }
                    }
                }
            }
            .padding(28)
        }
        .background(Vesper.background)
    }
}

struct SearchField: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Vesper.muted)
            TextField("Search moods, places, colors", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Vesper.muted)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct WallpaperCard: View {
    @EnvironmentObject private var catalog: CatalogStore
    let wallpaper: Wallpaper
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                thumb
                    .frame(height: 156)
                    .frame(maxWidth: .infinity)
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                Text(wallpaper.motionLabel.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(hovering ? Vesper.gold : Color.white.opacity(0.06), lineWidth: hovering ? 1.5 : 1)
            )
            Text(wallpaper.title).font(.callout.weight(.semibold)).foregroundStyle(Vesper.ink)
            Text(wallpaper.location).font(.caption).foregroundStyle(Vesper.muted).lineLimit(1)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(wallpaper.title), \(wallpaper.location)")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var thumb: some View {
        if let url = catalog.displayURL(wallpaper.thumbnail) {
            CatalogImage(url: url)
        } else {
            Rectangle().fill(Color.white.opacity(0.05))
        }
    }
}

struct HeroCard: View {
    @EnvironmentObject private var catalog: CatalogStore
    let wallpaper: Wallpaper
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            ZStack(alignment: .bottomLeading) {
                media
                    .frame(height: 420)
                    .frame(maxWidth: .infinity)
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 8) {
                    Text(wallpaper.motion == "footage" ? "PLAYING IN THE LIBRARY" : "FEATURED")
                        .font(.caption.weight(.semibold))
                        .tracking(1.1)
                        .foregroundStyle(Vesper.gold)
                    Text(wallpaper.title)
                        .font(.system(size: 40, weight: .medium, design: .serif))
                        .foregroundStyle(.white)
                    Text("\(wallpaper.location) · \(wallpaper.resolutionLabel)")
                        .foregroundStyle(.white.opacity(0.78))
                }
                .padding(28)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var media: some View {
        if let video = catalog.localFile(wallpaper.video) {
            LoopingPlayer(url: video)
        } else if let image = catalog.displayURL(wallpaper.image) {
            CatalogImage(url: image)
        } else {
            Color.black
        }
    }
}

struct CatalogImage: View {
    let url: URL
    var body: some View {
        if url.isFileURL, let image = ImageCache.shared.image(at: url) {
            Image(nsImage: image).resizable().scaledToFill()
        } else if !url.isFileURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Color.white.opacity(0.05)
                default:
                    ZStack {
                        Color.white.opacity(0.04)
                        ProgressView().controlSize(.small)
                    }
                }
            }
        } else {
            Color.white.opacity(0.05)
        }
    }
}

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, NSImage>()
    func image(at url: URL) -> NSImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

struct LoopingPlayer: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.play(url: url)
        return view
    }
    func updateNSView(_ view: PlayerView, context: Context) {
        view.play(url: url)
    }
}

struct PreviewPane: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var wallpaperController: WallpaperController
    let wallpaper: Wallpaper
    @Binding var display: DisplayTarget
    var onClose: () -> Void

    @State private var videoURL: URL?
    @State private var busy = false
    @State private var message: String?
    @State private var live = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    library.toggleFavorite(wallpaper.id)
                } label: {
                    Image(systemName: library.isFavorite(wallpaper.id) ? "heart.fill" : "heart")
                        .foregroundStyle(library.isFavorite(wallpaper.id) ? Vesper.gold : Vesper.ink)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    preview
                        .frame(height: 210)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Text(wallpaper.title)
                        .font(.system(size: 26, weight: .medium, design: .serif))
                    Text(wallpaper.location)
                        .foregroundStyle(Vesper.muted)
                    Text(wallpaper.resolutionLabel)
                        .font(.caption)
                        .foregroundStyle(Vesper.muted)
                    Text("\(wallpaper.motionLabel) · \(Int(wallpaper.duration)) seconds")
                        .font(.caption)
                        .foregroundStyle(Vesper.gold)
                    LabeledContent("By") { Text(wallpaper.author).multilineTextAlignment(.trailing) }
                        .font(.callout)
                    if let url = URL(string: wallpaper.licenseUrl), !wallpaper.license.isEmpty {
                        Link(wallpaper.license, destination: url)
                            .font(.callout)
                    }
                    if let source = URL(string: wallpaper.sourceUrl), !wallpaper.sourceUrl.isEmpty {
                        Link("Source", destination: source).font(.callout)
                    }
                    Picker("Display", selection: $display) {
                        Text("All displays").tag(DisplayTarget.all)
                        ForEach(wallpaperController.screens(), id: \.displayID) { screen in
                            Text(screen.localizedName).tag(DisplayTarget.display(screen.displayID))
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: wallpaperController.screenRevision) { _, _ in }
                    Toggle("Play the loop", isOn: $live)
                    Text(live
                         ? "The still becomes the desktop picture. The loop plays behind your icons."
                         : "Only the still image is set. Nothing keeps playing.")
                        .font(.caption)
                        .foregroundStyle(Vesper.muted)
                    if let message {
                        Text(message).font(.caption).foregroundStyle(.red)
                    }
                    Button {
                        Task { await apply() }
                    } label: {
                        Text(busy ? "Fetching…" : "Apply")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Vesper.gold)
                    .foregroundStyle(.black)
                    .disabled(busy)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .task(id: wallpaper.id) { await loadVideo() }
    }

    @ViewBuilder
    private var preview: some View {
        if let videoURL {
            LoopingPlayer(url: videoURL)
        } else if let image = catalog.displayURL(wallpaper.image) {
            ZStack {
                CatalogImage(url: image)
                if busy { ProgressView().controlSize(.small) }
            }
        } else {
            Color.black
        }
    }

    private func loadVideo() async {
        message = nil
        videoURL = catalog.localFile(wallpaper.video)
        if videoURL != nil { return }
        busy = true
        defer { busy = false }
        do {
            videoURL = try await catalog.ensureCached(wallpaper.video)
        } catch {
            message = error.localizedDescription
        }
    }

    private func apply() async {
        busy = true
        message = nil
        defer { busy = false }
        do {
            let still = try await catalog.ensureCached(wallpaper.image)
            let video = live ? try await catalog.ensureCached(wallpaper.video) : nil
            wallpaperController.apply(
                assignment: .init(
                    id: wallpaper.id,
                    title: wallpaper.title,
                    live: live && video != nil,
                    stillPath: still.path,
                    videoPath: video?.path
                ),
                target: display
            )
        } catch {
            message = error.localizedDescription
        }
    }
}

struct ImportsView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var importer = false
    @State private var targeted = false
    @State private var display: DisplayTarget = .all
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your Videos").font(.system(size: 28, weight: .medium, design: .serif))
                        Text("Drop an MP4, MOV, or M4V. It stays on this Mac and never uploads.").foregroundStyle(Vesper.muted)
                    }
                    Spacer()
                    Button("Import…") { importer = true }
                        .keyboardShortcut("i", modifiers: [.command])
                }
                if let error {
                    Text(error).foregroundStyle(.red).font(.callout)
                }
                dropWell
                if library.imports.isEmpty {
                    ContentUnavailableView("No videos yet", systemImage: "film", description: Text("A clip you import shows up here, then applies like any other wallpaper."))
                        .padding(.top, 12)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16)], spacing: 16) {
                        ForEach(library.imports) { clip in
                            ImportCard(clip: clip, display: display)
                        }
                    }
                }
            }
            .padding(28)
        }
        .background(Vesper.background)
        .fileImporter(isPresented: $importer, allowedContentTypes: [.mpeg4Movie, .quickTimeMovie, .movie]) { result in
            switch result {
            case .success(let url):
                Task {
                    do { try await library.importFile(at: url) } catch let importError { error = importError.localizedDescription }
                }
            case .failure(let failure):
                error = failure.localizedDescription
            }
        }
    }

    private var dropWell: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(targeted ? Vesper.gold : Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1.2, dash: [6]))
            .background(targeted ? Vesper.gold.opacity(0.08) : Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16))
            .frame(height: 92)
            .overlay { Text("Drop a video here").foregroundStyle(Vesper.muted) }
            .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                guard let provider = providers.first else { return false }
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else {
                        url = item as? URL
                    }
                    guard let url else { return }
                    Task { @MainActor in
                        do { try await library.importFile(at: url) } catch let importError { error = importError.localizedDescription }
                    }
                }
                return true
            }
    }
}

struct ImportCard: View {
    @EnvironmentObject private var wallpaper: WallpaperController
    let clip: ImportedClip
    let display: DisplayTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image = ImageCache.shared.image(at: URL(fileURLWithPath: clip.thumbPath)) {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(height: 140).frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Text(clip.title).font(.callout.weight(.semibold)).lineLimit(1)
            Button("Apply") {
                wallpaper.apply(
                    assignment: .init(
                        id: clip.id,
                        title: clip.title,
                        live: true,
                        stillPath: clip.stillPath,
                        videoPath: clip.videoPath
                    ),
                    target: display
                )
            }
            .buttonStyle(.bordered)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Settings").font(.system(size: 24, weight: .medium, design: .serif))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Text("Vesper reads wallpapers from a public GitHub repository. There is no account and no wallpaper server. Thumbnails load first. A loop is fetched when you preview or apply it, then kept in Application Support.")
                .font(.callout)
                .foregroundStyle(Vesper.muted)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Repository, owner/name or GitHub URL", text: $settings.repository)
                .textFieldStyle(.roundedBorder)
            TextField("Branch", text: $settings.branch)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Refresh catalog") { Task { await catalog.load() } }
                if catalog.usingRemoteManifest {
                    Text("Using the GitHub manifest").font(.caption).foregroundStyle(Vesper.gold)
                }
            }
            if let base = settings.remoteBase {
                Text(base.absoluteString).font(.caption).foregroundStyle(Vesper.muted).textSelection(.enabled)
            }
            Divider()
            Toggle("Pause the loop on battery and Low Power Mode", isOn: $settings.pauseOnBattery)
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
            if let login = settings.loginItemMessage {
                Text(login).font(.caption).foregroundStyle(.orange)
            }
            Picker("Rotate", selection: $settings.rotationMinutes) {
                Text("Off").tag(0)
                Text("Every 15 minutes").tag(15)
                Text("Every 30 minutes").tag(30)
                Text("Every hour").tag(60)
                Text("Every 3 hours").tag(180)
            }
            Text("Rotation walks your favorites, or the whole library if you have not hearted anything. It uses files already on disk.")
                .font(.caption)
                .foregroundStyle(Vesper.muted)
            Spacer()
            Text(catalog.sourceDescription).font(.caption).foregroundStyle(Vesper.muted)
        }
        .padding(24)
        .background(Vesper.background)
        .preferredColorScheme(.dark)
    }
}

struct MenuBarMenu: View {
    @EnvironmentObject private var wallpaper: WallpaperController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(wallpaper.activeTitle)
        Button(wallpaper.pausedByUser ? "Resume" : "Pause") { wallpaper.togglePause() }
            .keyboardShortcut("p")
            .disabled(wallpaper.pausedBySystem)
        if wallpaper.pausedBySystem {
            Text("Paused for battery, sleep, or the lock screen")
        }
        Divider()
        Button("Open Library") {
            openWindow(id: "library")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit Vesper") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
