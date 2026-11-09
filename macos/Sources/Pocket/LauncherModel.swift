import AppKit
import SwiftUI

/// One row in the results list.
struct ResultItem: Identifiable {
    enum Kind {
        /// `highlights` are character offsets in the app name that matched the query.
        case app(AppEntry, highlights: Set<Int>)
        case calculation(Calculator.Result)
        case webSearch(String)
    }

    let kind: Kind
    /// Header shown above the first row of each run of items with the same section.
    let section: String

    var id: String {
        switch kind {
        case .app(let app, _): return app.id
        case .calculation: return "pocket.calculator"
        case .webSearch: return "pocket.web-search"
        }
    }

    var app: AppEntry? {
        if case .app(let app, _) = kind { return app }
        return nil
    }

    var height: CGFloat {
        if case .calculation = kind { return PanelMetrics.calculationRowHeight }
        return PanelMetrics.rowHeight
    }
}

/// An entry in the ⌘K actions menu.
struct ActionItem: Identifiable {
    let title: String
    let symbol: String
    var shortcut: String? = nil
    var destructive = false
    let perform: () -> Void

    var id: String { title }
}

@MainActor
final class LauncherModel: ObservableObject {
    @Published var query = "" {
        didSet {
            showingActions = false
            mouseActive = false
            refilter()
        }
    }
    @Published private(set) var results: [ResultItem] = []
    @Published var selection = 0
    /// ⌘ held on its own: show the ⌘1–⌘9 badges.
    @Published var commandHeld = false
    @Published var showingActions = false {
        didSet { actionSelection = 0 }
    }
    @Published var actionSelection = 0
    /// Bundle IDs of running apps, for the running indicator and Quit / Hide.
    @Published private(set) var running: Set<String> = []
    /// A short confirmation ("Copied to Clipboard") shown in the footer before closing.
    @Published private(set) var toast: String?
    /// Drives the open animation.
    @Published var appeared = false
    /// Set by real mouse movement. Until then, rows ignore the pointer, so a cursor
    /// that just happens to sit over the list doesn't steal the selection.
    var mouseActive = false

    let config: Config
    var onFinish: () -> Void = {}

    private var apps: [AppEntry] = []
    private let usage = UsageStore()
    private var scanning = false
    private var finishToken = UUID()
    private var observers: [NSObjectProtocol] = []

    static let selectionAnimation = Animation.spring(response: 0.22, dampingFraction: 0.86)

    init(config: Config) {
        self.config = config
        reload()
        refreshRunning()

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.refreshRunning() }
                })
        }
    }

    deinit {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
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
        finishToken = UUID()
        toast = nil
        showingActions = false
        commandHeld = false
        appeared = false
        mouseActive = false
        query = ""
        selection = 0
        refreshRunning()
    }

    private func refreshRunning() {
        running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    func isRunning(_ app: AppEntry) -> Bool {
        app.bundleID.map(running.contains) ?? false
    }

    // MARK: - Results

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
            results =
                recent.map { ResultItem(kind: .app($0, highlights: []), section: "Recent") }
                + apps.filter { !recentIDs.contains($0.id) }.map {
                    ResultItem(kind: .app($0, highlights: []), section: "Applications")
                }
        } else {
            var items: [ResultItem] = []
            if let result = Calculator.evaluate(q) {
                items.append(ResultItem(kind: .calculation(result), section: "Calculator"))
            }
            items += apps.compactMap { app -> (AppEntry, Int)? in
                let best = ([app.name] + app.aliases)
                    .compactMap { Matcher.score(query: q, name: $0) }
                    .max()
                guard let best else { return nil }
                return (app, best + usage.boost(for: app))
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.name < $1.0.name }
            .prefix(config.maxResults)
            .map {
                let highlights = Matcher.highlights(query: q, name: $0.0.name)
                return ResultItem(kind: .app($0.0, highlights: highlights), section: "Applications")
            }
            if items.isEmpty {
                items.append(ResultItem(kind: .webSearch(q), section: "Web"))
            }
            results = items
        }

        if let selectedID, let index = results.firstIndex(where: { $0.id == selectedID }) {
            selection = index
        } else {
            selection = 0
        }
    }

    var selectedItem: ResultItem? {
        results.indices.contains(selection) ? results[selection] : nil
    }

    /// The whole panel's height: it shrinks to fit a short list of results.
    var panelHeight: CGFloat {
        var list: CGFloat = 0
        if !results.isEmpty {
            list = PanelMetrics.listPadding * 2 + results.reduce(0) { $0 + $1.height }
            var previous: String?
            for item in results where item.section != previous {
                list += PanelMetrics.headerHeight
                previous = item.section
            }
        }
        let chrome = PanelMetrics.searchHeight + PanelMetrics.footerHeight
        var height = chrome + min(list, PanelMetrics.maxHeight - chrome)
        if showingActions {
            // Keep the actions menu inside the panel even when the list is short.
            let menu = CGFloat(actions.count) * PanelMetrics.actionRowHeight + 52
            height = max(height, chrome + menu)
        }
        return height
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        mouseActive = false
        withAnimation(Self.selectionAnimation) {
            selection = (selection + delta + results.count) % results.count
        }
    }

    // MARK: - Actions

    var primaryActionTitle: String {
        switch selectedItem?.kind {
        case .app: return "Open Application"
        case .calculation: return "Copy Answer"
        case .webSearch: return "Search the Web"
        case nil: return "Open"
        }
    }

    /// Runs the default action for the row at `index` (or the selected row).
    func activate(at index: Int? = nil) {
        let index = index ?? selection
        guard results.indices.contains(index) else { return }
        switch results[index].kind {
        case .app(let app, _): open(app)
        case .calculation(let result): copy(result.plain)
        case .webSearch(let query): searchWeb(query)
        }
    }

    func revealSelected() {
        guard let app = selectedItem?.app else { return }
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
        onFinish()
    }

    /// ⌘⇧C: the selected app's path, or the full calculation.
    func copySecondary() {
        switch selectedItem?.kind {
        case .app(let app, _): copy(app.url.path)
        case .calculation(let result): copy("\(result.expression) = \(result.plain)")
        default: break
        }
    }

    /// ⌘C with nothing selected in the search field copies the answer.
    func copyAnswerIfCalculation() -> Bool {
        guard case .calculation(let result) = selectedItem?.kind else { return false }
        copy(result.plain)
        return true
    }

    var actions: [ActionItem] {
        switch selectedItem?.kind {
        case .app(let app, _):
            var list = [
                ActionItem(title: "Open Application", symbol: "arrow.up.forward.app", shortcut: "↵") { [weak self] in
                    self?.open(app)
                },
                ActionItem(title: "Show in Finder", symbol: "folder", shortcut: "⌘↵") { [weak self] in
                    self?.revealSelected()
                },
                ActionItem(title: "Copy Path", symbol: "doc.on.doc", shortcut: "⌘⇧C") { [weak self] in
                    self?.copy(app.url.path)
                },
            ]
            if let running = runningApplication(app) {
                list.append(
                    ActionItem(title: "Hide Application", symbol: "eye.slash") { [weak self] in
                        running.hide()
                        self?.onFinish()
                    })
                list.append(
                    ActionItem(title: "Quit Application", symbol: "xmark.circle", destructive: true) { [weak self] in
                        running.terminate()
                        self?.finish(toast: "Quitting \(app.name)…")
                    })
            }
            return list
        case .calculation(let result):
            return [
                ActionItem(title: "Copy Answer", symbol: "doc.on.doc", shortcut: "↵") { [weak self] in
                    self?.copy(result.plain)
                },
                ActionItem(title: "Copy Calculation", symbol: "equal.square", shortcut: "⌘⇧C") { [weak self] in
                    self?.copy("\(result.expression) = \(result.plain)")
                },
            ]
        case .webSearch(let query):
            return [
                ActionItem(title: "Search the Web", symbol: "globe", shortcut: "↵") { [weak self] in
                    self?.searchWeb(query)
                }
            ]
        case nil:
            return []
        }
    }

    func toggleActions() {
        guard selectedItem != nil else { return }
        showingActions.toggle()
    }

    func moveAction(_ delta: Int) {
        let count = actions.count
        guard count > 0 else { return }
        withAnimation(Self.selectionAnimation) {
            actionSelection = (actionSelection + delta + count) % count
        }
    }

    func runAction(at index: Int? = nil) {
        let list = actions
        let index = index ?? actionSelection
        guard list.indices.contains(index) else { return }
        showingActions = false
        list[index].perform()
    }

    // MARK: - Effects

    private func open(_ app: AppEntry) {
        usage.record(app)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { _, error in
            if let error { NSLog("Pocket: failed to open \(app.name): \(error.localizedDescription)") }
        }
        onFinish()
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        finish(toast: "Copied to Clipboard")
    }

    private func searchWeb(_ query: String) {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(["&", "+", "=", "?", "#"])) ?? query
        if let url = URL(string: config.searchURL.replacingOccurrences(of: "%s", with: encoded)) {
            NSWorkspace.shared.open(url)
        }
        onFinish()
    }

    private func runningApplication(_ app: AppEntry) -> NSRunningApplication? {
        guard let id = app.bundleID, running.contains(id) else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).first
    }

    /// Shows `toast` in the footer briefly, then closes — unless the panel was
    /// reopened in the meantime.
    private func finish(toast: String) {
        self.toast = toast
        let token = UUID()
        finishToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.finishToken == token else { return }
            self.onFinish()
        }
    }
}
