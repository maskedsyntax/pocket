import AppKit
import SwiftUI

enum PanelMetrics {
    static let width: CGFloat = 680
    static let height: CGFloat = 460
    static let cornerRadius: CGFloat = 26
}

/// One type scale for the whole panel, derived from `font` / `font-size` so a
/// custom font keeps the same hierarchy. Sizes follow the search text size
/// (default 22pt); the small print stays SF Pro for legibility.
struct Typography {
    let search: NSFont
    let title: Font
    let subtitle: Font
    let caption: Font
    let captionStrong: Font

    init(_ config: Config) {
        let base = config.fontSize
        search = config.nsFont(size: base, weight: .regular)
        title = Font(config.nsFont(size: (base * 0.64).rounded(), weight: .medium))
        subtitle = .system(size: max(11, (base * 0.52).rounded()), weight: .regular)
        caption = .system(size: 11, weight: .regular)
        captionStrong = .system(size: 11, weight: .medium).monospacedDigit()
    }
}

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    let onSearchFieldReady: (NSTextField) -> Void

    private var config: Config { model.config }
    private var type: Typography { Typography(model.config) }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.6)
            if model.results.isEmpty {
                emptyState
            } else {
                resultList
            }
            footer
        }
        .frame(width: PanelMetrics.width, height: PanelMetrics.height)
        .background(LauncherBackground(style: config.style, cornerRadius: PanelMetrics.cornerRadius))
        .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(config.style == .solid ? 0.08 : 0.18), lineWidth: 1)
        )
    }

    private var searchBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: (config.fontSize * 0.86).rounded(), weight: .semibold))
                .foregroundStyle(.tertiary)
            SearchField(
                text: $model.query,
                placeholder: "Search apps",
                font: type.search,
                onReady: onSearchFieldReady
            )
        }
        .padding(.horizontal, 22)
        .frame(height: 64)
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, app in
                        ResultRow(
                            app: app,
                            index: index,
                            selected: index == model.selection,
                            config: config,
                            type: type
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { model.launch(at: index) }
                        .onHover { if $0 { model.selection = index } }
                    }
                }
                .padding(8)
            }
            // Rows are identified by app (the ForEach id), never by position:
            // an index id makes the lazy stack reuse stale rows after filtering.
            .onChange(of: model.selection) { index in
                guard model.results.indices.contains(index) else { return }
                proxy.scrollTo(model.results[index].id)
            }
            .onChange(of: model.query) { _ in
                if let first = model.results.first { proxy.scrollTo(first.id, anchor: .top) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: model.query.isEmpty ? "hourglass" : "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(model.query.isEmpty ? "Indexing applications…" : "No apps match “\(model.query)”")
                .font(type.title)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                if let icon = NSImage(named: "AppIcon") {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                }
                Text("Pocket").font(type.captionStrong)
            }
            .foregroundStyle(.secondary)
            Spacer()
            KeyHint(keys: "↵", label: "Open", type: type)
            KeyHint(keys: "⌘↵", label: "Show in Finder", type: type)
            KeyHint(keys: "⌘1–9", label: "Quick open", type: type)
            KeyHint(keys: "esc", label: "Close", type: type)
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(Color.primary.opacity(0.04))
        .overlay(alignment: .top) { Divider().opacity(0.6) }
    }
}

private struct ResultRow: View {
    let app: AppEntry
    let index: Int
    let selected: Bool
    let config: Config
    let type: Typography

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: IconCache.icon(for: app.url))
                .resizable()
                .interpolation(.high)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(type.title)
                    .foregroundStyle(selected && config.accent != nil ? Color.white : Color.primary)
                    .lineLimit(1)
                Text(app.location)
                    .font(type.subtitle)
                    .foregroundStyle(
                        selected && config.accent != nil ? Color.white.opacity(0.7) : Color.secondary
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(type.captionStrong)
                    .foregroundStyle(
                        selected && config.accent != nil ? Color.white.opacity(0.8) : Color.secondary
                    )
                    .opacity(selected ? 1 : 0.55)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(highlight)
        )
    }

    private var highlight: Color {
        guard selected else { return .clear }
        if let accent = config.accent { return Color(nsColor: accent).opacity(0.9) }
        return Color.primary.opacity(0.11)
    }
}

private struct KeyHint: View {
    let keys: String
    let label: String
    let type: Typography

    var body: some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(type.captionStrong)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
            Text(label)
                .font(type.caption)
        }
        .foregroundStyle(.secondary)
    }
}

/// A borderless NSTextField so we control focus and get native text editing.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let font: NSFont
    let onReady: (NSTextField) -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = font
        field.cell?.usesSingleLineMode = true
        field.cell?.lineBreakMode = .byTruncatingTail
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
        )
        field.delegate = context.coordinator
        onReady(field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
