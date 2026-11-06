import AppKit
import SwiftUI

@main
struct VesperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var catalog: CatalogStore
    @StateObject private var library: LibraryStore
    @StateObject private var wallpaper = WallpaperController.shared

    init() {
        let settings = SettingsStore.shared
        _catalog = StateObject(wrappedValue: CatalogStore(settings: settings))
        _library = StateObject(wrappedValue: LibraryStore())
    }

    var body: some Scene {
        WindowGroup(id: "library") {
            RootView()
                .environmentObject(settings)
                .environmentObject(catalog)
                .environmentObject(library)
                .environmentObject(wallpaper)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1220, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Wallpaper") {
                Button(wallpaper.pausedByUser ? "Resume" : "Pause") {
                    wallpaper.togglePause()
                }
                .keyboardShortcut("p", modifiers: [.command])
            }
        }

        MenuBarExtra {
            MenuBarMenu()
                .environmentObject(wallpaper)
        } label: {
            Image(systemName: wallpaper.isPlaying ? "moon.stars.fill" : "moon.stars")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(catalog)
                .frame(width: 520, height: 560)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            WallpaperController.shared.reassertOrder()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidBecomeActive(_ notification: Notification) {
        WallpaperController.shared.reassertOrder()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where window.canBecomeKey {
                window.makeKeyAndOrderFront(nil)
            }
            sender.activate(ignoringOtherApps: true)
        }
        return true
    }
}
