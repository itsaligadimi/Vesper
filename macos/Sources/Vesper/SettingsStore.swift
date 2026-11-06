import Foundation
import ServiceManagement

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var repository: String {
        didSet { defaults.set(repository, forKey: Key.repository) }
    }
    @Published var branch: String {
        didSet { defaults.set(branch, forKey: Key.branch) }
    }
    @Published var pauseOnBattery: Bool {
        didSet { defaults.set(pauseOnBattery, forKey: Key.pauseOnBattery) }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            guard !suppressLoginWrite else { return }
            updateLoginItem()
        }
    }
    @Published var rotationMinutes: Int {
        didSet { defaults.set(rotationMinutes, forKey: Key.rotation) }
    }
    @Published var loginItemMessage: String?

    private let defaults = UserDefaults.standard
    private var suppressLoginWrite = false

    private enum Key {
        static let repository = "vesper.repository"
        static let branch = "vesper.branch"
        static let pauseOnBattery = "vesper.pauseOnBattery"
        static let rotation = "vesper.rotationMinutes"
    }

    private init() {
        let defaults = UserDefaults.standard
        repository = defaults.string(forKey: Key.repository) ?? ""
        branch = defaults.string(forKey: Key.branch) ?? "main"
        pauseOnBattery = defaults.object(forKey: Key.pauseOnBattery) as? Bool ?? true
        rotationMinutes = defaults.object(forKey: Key.rotation) as? Int ?? 0
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func applySourceFile(_ source: CatalogSourceFile) {
        if repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            repository = source.repository
        }
        if branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            branch = source.branch.isEmpty ? "main" : source.branch
        }
    }

    var remoteBase: URL? {
        guard let parsed = RepositoryParser.parse(repository) else { return nil }
        return RepositoryParser.catalogBase(owner: parsed.owner, name: parsed.name, branch: branch)
    }

    private func updateLoginItem() {
        loginItemMessage = nil
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginItemMessage = "Launch at login needs Vesper in your Applications folder. \(error.localizedDescription)"
            suppressLoginWrite = true
            launchAtLogin = SMAppService.mainApp.status == .enabled
            suppressLoginWrite = false
        }
    }
}
