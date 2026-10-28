import AppKit
import Combine

@MainActor
final class LauncherModel: ObservableObject {
    @Published var query = "" {
        didSet { refilter() }
    }
    @Published private(set) var results: [AppEntry] = []
    @Published var selection = 0

    let config: Config
    var onFinish: () -> Void = {}

    private var apps: [AppEntry] = []
    private let usage = UsageStore()
    private var scanning = false

    init(config: Config) {
        self.config = config
        reload()
    }

    /// Rescans application folders in the background. Called on launch and every
    /// time the panel opens, so newly installed apps show up without a restart.
    func reload() {
        guard !scanning else { return }
        scanning = true
        let dirs = config.appDirs
        Task.detached(priority: .userInitiated) {
            let apps = AppIndex.scan(extraDirs: dirs)
            await MainActor.run {
                self.apps = apps
                self.scanning = false
                self.refilter(keepSelection: true)
            }
        }
    }

    func reset() {
        query = ""
        selection = 0
    }

    private func refilter(keepSelection: Bool = false) {
        let selectedID = keepSelection && results.indices.contains(selection) ? results[selection].id : nil
        let q = query.trimmingCharacters(in: .whitespaces)

        if q.isEmpty {
            // Recently used apps first, then every other app alphabetically.
            // No max-results cap here: browsing should reach the whole list.
            let recent = apps.filter { usage.lastUsed($0) != nil }
                .sorted { usage.lastUsed($0)! > usage.lastUsed($1)! }
                .prefix(8)
            let recentIDs = Set(recent.map(\.id))
            results = Array(recent) + apps.filter { !recentIDs.contains($0.id) }
        } else {
            results = apps.compactMap { app -> (AppEntry, Int)? in
                let best = ([app.name] + app.aliases)
                    .compactMap { Matcher.score(query: q, name: $0) }
                    .max()
                guard let best else { return nil }
                return (app, best + usage.boost(for: app))
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.name < $1.0.name }
            .prefix(config.maxResults)
            .map(\.0)
        }

        if let selectedID, let index = results.firstIndex(where: { $0.id == selectedID }) {
            selection = index
        } else {
            selection = 0
        }
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    func launch(at index: Int? = nil) {
        let index = index ?? selection
        guard results.indices.contains(index) else { return }
        let app = results[index]
        usage.record(app)

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { _, error in
            if let error { NSLog("Pocket: failed to open \(app.name): \(error.localizedDescription)") }
        }
        onFinish()
    }

    func revealSelected() {
        guard results.indices.contains(selection) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([results[selection].url])
        onFinish()
    }
}
