import AppKit
import AVFoundation
import CoreGraphics
import IOKit.ps

/// Plays a silent loop in a borderless window parked between the desktop picture and the icons.
/// The matching still is also set as the real desktop picture, so the menu bar tint stays honest
/// and a picture remains if Vesper quits.
@MainActor
final class WallpaperController: ObservableObject {
    static let shared = WallpaperController()

    @Published private(set) var pausedByUser = false
    @Published private(set) var pausedBySystem = false
    @Published private(set) var activeTitle: String = "Nothing playing"
    @Published private(set) var screenRevision = 0

    private var windows: [CGDirectDisplayID: WallpaperWindow] = [:]
    private var assignments: [CGDirectDisplayID: Assignment] = [:]
    private var mirrorAll = false
    private var rotationTimer: Timer?
    private let stateURL: URL

    struct Assignment: Codable {
        var id: String
        var title: String
        var live: Bool
        var stillPath: String
        var videoPath: String?
    }

    private struct Persisted: Codable {
        var mirrorAll: Bool
        var assignments: [String: Assignment]
    }

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vesper", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        stateURL = support.appendingPathComponent("playback.json")
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pausedBySystem = true; self?.syncPlayback() }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshSystemPause(); self?.syncPlayback() }
        }
        center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pausedBySystem = true; self?.syncPlayback() }
        }
        center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshSystemPause(); self?.syncPlayback() }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.pausedBySystem = true; self?.syncPlayback() }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshSystemPause(); self?.syncPlayback() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.screenRevision += 1
                self?.relayout()
            }
        }
    }

    var isPlaying: Bool { !pausedByUser && !pausedBySystem && windows.values.contains { $0.isPlaying } }

    func screens() -> [NSScreen] { NSScreen.screens }

    func restore() {
        guard let data = try? Data(contentsOf: stateURL),
              let saved = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        mirrorAll = saved.mirrorAll
        assignments = Dictionary(uniqueKeysWithValues: saved.assignments.compactMap { key, value in
            guard let id = UInt32(key) else { return nil }
            return (id, value)
        })
        refreshSystemPause()
        relayout()
    }

    func apply(assignment: Assignment, target: DisplayTarget) {
        let targets = screens(for: target)
        mirrorAll = target == .all
        for screen in targets {
            let id = screen.displayID
            assignments[id] = assignment
            setDesktopImage(URL(fileURLWithPath: assignment.stillPath), on: screen)
        }
        activeTitle = assignment.title
        pausedByUser = false
        refreshSystemPause()
        relayout()
        persist()
    }

    func togglePause() {
        pausedByUser.toggle()
        syncPlayback()
        persist()
    }

    func configureRotation(minutes: Int, next: @escaping () -> Assignment?) {
        rotationTimer?.invalidate()
        rotationTimer = nil
        guard minutes > 0 else { return }
        rotationTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let assignment = next() else { return }
                self.apply(assignment: assignment, target: .all)
            }
        }
    }

    func reassertOrder() {
        for window in windows.values {
            window.reassert()
        }
    }

    private func screens(for target: DisplayTarget) -> [NSScreen] {
        switch target {
        case .all:
            return NSScreen.screens
        case .display(let id):
            return NSScreen.screens.filter { $0.displayID == id }
        }
    }

    private func relayout() {
        let liveIDs = Set(NSScreen.screens.map(\.displayID))
        for id in windows.keys where !liveIDs.contains(id) {
            windows[id]?.close()
            windows[id] = nil
        }
        for screen in NSScreen.screens {
            let id = screen.displayID
            guard let assignment = assignments[id] else {
                windows[id]?.close()
                windows[id] = nil
                continue
            }
            let window = windows[id] ?? WallpaperWindow(screen: screen)
            windows[id] = window
            window.update(screen: screen)
            if assignment.live, let path = assignment.videoPath {
                window.play(url: URL(fileURLWithPath: path))
            } else {
                window.stop()
            }
        }
        syncPlayback()
    }

    private func syncPlayback() {
        let shouldPlay = !pausedByUser && !pausedBySystem
        for window in windows.values {
            if shouldPlay {
                window.resume()
            } else {
                window.pause()
            }
        }
    }

    private func refreshSystemPause() {
        let settings = SettingsStore.shared
        let battery = settings.pauseOnBattery && (Self.onBattery || ProcessInfo.processInfo.isLowPowerModeEnabled)
        pausedBySystem = battery
    }

    private func setDesktopImage(_ url: URL, on screen: NSScreen) {
        try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
    }

    private func persist() {
        let encoded = Dictionary(uniqueKeysWithValues: assignments.map { (String($0.key), $0.value) })
        let payload = Persisted(mirrorAll: mirrorAll, assignments: encoded)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }

    private static var onBattery: Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return false }
        guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            let state = description[kIOPSPowerSourceStateKey as String] as? String
            if state == kIOPSBatteryPowerValue as String { return true }
        }
        return false
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? 0
    }
}

private final class WallpaperWindow: NSWindow {
    private let playerView = PlayerView(frame: .zero)
    private(set) var isPlaying = false

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        canHide = false
        isMovable = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        contentView = playerView
        playerView.autoresizingMask = [.width, .height]
        update(screen: screen)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(screen: NSScreen) {
        setFrame(screen.frame, display: true)
        reassert()
    }

    func reassert() {
        // desktopIconWindow sits above the picture. One level below it is behind the icons
        // and above the system wallpaper. The still image is set separately, so this window
        // only has to cover that picture.
        let iconLevel = CGWindowLevelForKey(.desktopIconWindow)
        level = NSWindow.Level(rawValue: Int(iconLevel) - 1)
        orderBack(nil)
    }

    func play(url: URL) {
        playerView.play(url: url)
        isPlaying = true
        orderBack(nil)
    }

    func pause() {
        playerView.pause()
        isPlaying = false
    }

    func resume() {
        guard playerView.hasPlayer else { return }
        playerView.resume()
        isPlaying = true
        orderBack(nil)
    }

    func stop() {
        playerView.stop()
        isPlaying = false
        orderOut(nil)
    }
}

final class PlayerView: NSView {
    private var queue: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var currentURL: URL?

    var hasPlayer: Bool { queue != nil }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func makeBackingLayer() -> CALayer {
        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspectFill
        layer.backgroundColor = NSColor.black.cgColor
        return layer
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func play(url: URL) {
        if currentURL == url, queue != nil { return }
        currentURL = url
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.volume = 0
        looper = AVPlayerLooper(player: queue, templateItem: item)
        self.queue = queue
        playerLayer.player = queue
        queue.play()
    }

    func pause() { queue?.pause() }

    func resume() { queue?.play() }

    func stop() {
        queue?.pause()
        playerLayer.player = nil
        queue = nil
        looper = nil
        currentURL = nil
    }
}
