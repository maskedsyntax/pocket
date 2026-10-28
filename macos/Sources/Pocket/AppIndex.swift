import AppKit

struct AppEntry: Identifiable, Hashable {
    let url: URL
    let name: String
    /// Extra names to match against, e.g. the bundle's on-disk name when the
    /// display name is localized ("Calculator" vs "Rechner").
    let aliases: [String]
    let location: String

    var id: String { url.path }
}

enum AppIndex {
    static let defaultDirs = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        "/System/Library/CoreServices/Applications",
        NSString(string: "~/Applications").expandingTildeInPath,
    ]

    /// Apps that live outside the usual folders but people expect to find.
    static let extraApps = [
        "/System/Library/CoreServices/Finder.app"
    ]

    /// A short, human label for where an app lives instead of a raw path:
    /// "/System/Applications/Utilities" → "Utilities", "/Applications/Setapp" → "Applications › Setapp".
    static func locationLabel(for folder: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch folder {
        case "/Applications": return "Applications"
        case "/Applications/Utilities", "/System/Applications/Utilities": return "Utilities"
        case "/System/Applications": return "System"
        case "/System/Library/CoreServices", "/System/Library/CoreServices/Applications":
            return "System · Core Services"
        case home + "/Applications": return "Home · Applications"
        default:
            if folder.hasPrefix("/Applications/") {
                return "Applications › " + folder.dropFirst("/Applications/".count)
            }
            return folder.replacingOccurrences(of: home, with: "~")
        }
    }

    static func scan(extraDirs: [String]) -> [AppEntry] {
        let fm = FileManager.default
        var seen = Set<String>()
        var apps: [AppEntry] = []

        func add(_ url: URL) {
            let url = url.resolvingSymlinksInPath()
            let bundle = Bundle(url: url)
            let key = bundle?.bundleIdentifier ?? url.path
            guard seen.insert(key).inserted else { return }

            let fileName = url.deletingPathExtension().lastPathComponent
            var name = fm.displayName(atPath: url.path)
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }

            var aliases: [String] = []
            if fileName != name { aliases.append(fileName) }
            if let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String,
                bundleName != name, bundleName != fileName
            {
                aliases.append(bundleName)
            }

            let location = locationLabel(for: url.deletingLastPathComponent().path)
            apps.append(AppEntry(url: url, name: name, aliases: aliases, location: location))
        }

        for dir in defaultDirs + extraDirs {
            let root = URL(fileURLWithPath: dir)
            guard
                let enumerator = fm.enumerator(
                    at: root, includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { continue }

            for case let url as URL in enumerator {
                if url.pathExtension == "app" {
                    add(url)
                    enumerator.skipDescendants()
                } else if enumerator.level >= 2 {
                    // Look one folder deep (e.g. /Applications/Setapp), no further.
                    enumerator.skipDescendants()
                }
            }
        }
        for path in extraApps where fm.fileExists(atPath: path) {
            add(URL(fileURLWithPath: path))
        }

        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// NSWorkspace icon lookups are cheap but not free; cache them per path.
@MainActor
enum IconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for url: URL) -> NSImage {
        if let image = cache.object(forKey: url.path as NSString) {
            return image
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(image, forKey: url.path as NSString)
        return image
    }
}
