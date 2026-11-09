import AppKit
import SwiftUI

enum PanelMetrics {
    static let width: CGFloat = 680
    /// The tallest the panel gets; it shrinks to fit shorter result lists.
    static let maxHeight: CGFloat = 474
    static let cornerRadius: CGFloat = 22

    static let searchHeight: CGFloat = 50
    static let footerHeight: CGFloat = 40
    static let rowHeight: CGFloat = 40
    static let calculationRowHeight: CGFloat = 64
    static let headerHeight: CGFloat = 28
    static let listPadding: CGFloat = 6
    static let actionRowHeight: CGFloat = 30
}

/// One type scale for the whole panel, derived from `font` / `font-size` so a
/// custom font keeps the same hierarchy. Sizes follow the search text size
/// (default 18pt); the small print stays SF Pro for legibility.
struct Typography {
    let search: NSFont
    let title: Font
    let titleMatch: Font
    let caption: Font
    let captionStrong: Font
    let header: Font

    init(_ config: Config) {
        let base = config.fontSize
        let titleSize = (base * 0.78).rounded()
        search = config.nsFont(size: base, weight: .regular)
        title = Font(config.nsFont(size: titleSize, weight: .regular))
        titleMatch = Font(config.nsFont(size: titleSize, weight: .bold))
        caption = .system(size: 12, weight: .regular)
        captionStrong = .system(size: 11, weight: .medium).monospacedDigit()
        header = .system(size: 11, weight: .semibold)
    }
}

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    let onSearchFieldReady: (NSTextField) -> Void
    let onHeightChange: (CGFloat) -> Void

    @Namespace private var selectionSpace

    private var config: Config { model.config }
    private var type: Typography { Typography(model.config) }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if !model.results.isEmpty {
                resultList
            } else {
                Spacer(minLength: 0)
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay {
            if model.showingActions {
                // Clicking anywhere outside the menu closes it.
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { model.showingActions = false }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if model.showingActions {
                ActionMenu(model: model, type: type)
                    .padding(.trailing, 10)
                    .padding(.bottom, PanelMetrics.footerHeight + 6)
                    .transition(.scale(scale: 0.96, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.12), value: model.showingActions)
        .background(LauncherBackground(style: config.style, cornerRadius: PanelMetrics.cornerRadius))
        .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(config.style == .solid ? 0.08 : 0.16), lineWidth: 1)
        )
        .scaleEffect(model.appeared ? 1 : 0.97, anchor: .top)
        .onAppear { onHeightChange(model.panelHeight) }
        .onChange(of: model.panelHeight) { onHeightChange($0) }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: (config.fontSize * 0.85).rounded(), weight: .medium))
                .foregroundStyle(.tertiary)
            SearchField(
                text: $model.query,
                placeholder: "Search apps or calculate…",
                font: type.search,
                onReady: onSearchFieldReady
            )
        }
        .padding(.horizontal, 18)
        .frame(height: PanelMetrics.searchHeight)
        .overlay(alignment: .bottom) { Hairline() }
    }

    // MARK: - Results

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    Color.clear.frame(height: PanelMetrics.listPadding).id("top")
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                        if index == 0 || model.results[index - 1].section != item.section {
                            SectionHeader(title: item.section, type: type)
                        }
                        row(item, index: index)
                    }
                    Color.clear.frame(height: PanelMetrics.listPadding)
                }
                .padding(.horizontal, 8)
            }
            .mask(EdgeFade())
            // Rows are identified by item, never by position: an index id makes
            // the lazy stack reuse stale rows after filtering.
            .onChange(of: model.selection) { index in
                guard model.results.indices.contains(index) else { return }
                if index == 0 {
                    proxy.scrollTo("top", anchor: .top)  // bring the first header back too
                } else {
                    proxy.scrollTo(model.results[index].id)
                }
            }
            .onChange(of: model.query) { _ in
                proxy.scrollTo("top", anchor: .top)
            }
        }
    }

    private func row(_ item: ResultItem, index: Int) -> some View {
        let selected = index == model.selection
        return Group {
            switch item.kind {
            case .app(let app, let highlights):
                AppRow(
                    app: app, highlights: highlights, running: model.isRunning(app),
                    type: type, selected: selected)
            case .calculation(let result):
                CalculationRow(result: result, type: type)
            case .webSearch(let query):
                WebSearchRow(query: query, type: type)
            }
        }
        .overlay(alignment: .trailing) {
            if model.commandHeld && index < 9 {
                KeyChip(keys: "⌘\(index + 1)", type: type).padding(.trailing, 10)
            }
        }
        .frame(height: item.height)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(highlight)
                    .matchedGeometryEffect(id: "selection", in: selectionSpace)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.activate(at: index) }
        .onContinuousHover { phase in
            guard case .active = phase, model.mouseActive, !model.showingActions,
                model.selection != index
            else { return }
            withAnimation(LauncherModel.selectionAnimation) { model.selection = index }
        }
        .id(item.id)
    }

    private var highlight: Color {
        if let accent = config.accent { return Color(nsColor: accent).opacity(0.3) }
        return Color.primary.opacity(0.09)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            footerStatus
            Spacer(minLength: 12)
            FooterButton(label: model.primaryActionTitle, keys: "↵", type: type) { model.activate() }
                .disabled(model.selectedItem == nil)
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 14)
            FooterButton(label: "Actions", keys: "⌘K", type: type) { model.toggleActions() }
                .disabled(model.selectedItem == nil)
        }
        .padding(.horizontal, 14)
        .frame(height: PanelMetrics.footerHeight)
        .background(Color.primary.opacity(0.03))
        .overlay(alignment: .top) { Hairline() }
    }

    @ViewBuilder private var footerStatus: some View {
        if let toast = model.toast {
            Label(toast, systemImage: "checkmark.circle.fill")
                .font(type.caption.weight(.medium))
                .foregroundStyle(.primary)
                .transition(.opacity)
        } else {
            HStack(spacing: 7) {
                switch model.selectedItem?.kind {
                case .app(let app, _):
                    Image(nsImage: IconCache.icon(for: app.url)).resizable().frame(width: 16, height: 16)
                    Text(app.name)
                case .calculation:
                    Image(systemName: "equal.square.fill").foregroundStyle(.orange)
                    Text("Calculator")
                case .webSearch:
                    Image(systemName: "globe")
                    Text("Web Search")
                case nil:
                    if let icon = NSImage(named: "AppIcon") {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    }
                    Text("Pocket")
                }
            }
            .font(type.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }
}

// MARK: - Rows

private struct SectionHeader: View {
    let title: String
    let type: Typography

    var body: some View {
        Text(title)
            .font(type.header)
            .foregroundStyle(.secondary)
            .padding(.leading, 12)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, minHeight: PanelMetrics.headerHeight,
                   maxHeight: PanelMetrics.headerHeight, alignment: .bottomLeading)
    }
}

private struct AppRow: View {
    let app: AppEntry
    let highlights: Set<Int>
    let running: Bool
    let type: Typography
    let selected: Bool

    /// The common folders are implied by the section header; only call out the rest.
    private static let quietLocations: Set<String> = [
        "Applications", "System", "Utilities", "Home · Applications", "System · Core Services",
    ]

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: IconCache.icon(for: app.url))
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
            Text(name).lineLimit(1)
            if running {
                Circle()
                    .fill(Color.primary.opacity(0.45))
                    .frame(width: 5, height: 5)
                    .help("Running")
            }
            Spacer(minLength: 8)
            if !Self.quietLocations.contains(app.location) {
                Text(app.location)
                    .font(type.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 10)
    }

    /// The app name with the letters that matched the query in bold.
    private var name: AttributedString {
        guard !highlights.isEmpty else {
            var plain = AttributedString(app.name)
            plain.font = type.title
            return plain
        }
        var result = AttributedString()
        for (offset, ch) in app.name.enumerated() {
            var piece = AttributedString(String(ch))
            let matched = highlights.contains(offset)
            piece.font = matched ? type.titleMatch : type.title
            piece.foregroundColor = matched ? .primary : .primary.opacity(0.78)
            result += piece
        }
        return result
    }
}

private struct CalculationRow: View {
    let result: Calculator.Result
    let type: Typography

    var body: some View {
        HStack(spacing: 12) {
            RowBadge(symbol: "equal", color: .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.display)
                    .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .textSelection(.enabled)
                Text(result.expression)
                    .font(type.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
    }
}

private struct WebSearchRow: View {
    let query: String
    let type: Typography

    var body: some View {
        HStack(spacing: 10) {
            RowBadge(symbol: "globe", color: .blue)
            (Text("Search the web for ") + Text("“\(query)”").font(type.titleMatch))
                .font(type.title)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
    }
}

/// A coloured rounded square with a symbol, standing in for an app icon.
private struct RowBadge: View {
    let symbol: String
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(color.gradient)
            .frame(width: 26, height: 26)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - Actions menu

private struct ActionMenu: View {
    @ObservedObject var model: LauncherModel
    let type: Typography

    var body: some View {
        let actions = model.actions
        VStack(alignment: .leading, spacing: 0) {
            Text("Actions")
                .font(type.header)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 26, alignment: .center)
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                HStack(spacing: 10) {
                    Image(systemName: action.symbol)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 16)
                    Text(action.title).font(type.caption)
                    Spacer(minLength: 8)
                    if let shortcut = action.shortcut {
                        KeyChip(keys: shortcut, type: type)
                    }
                }
                .foregroundStyle(action.destructive ? Color.red : Color.primary)
                .padding(.horizontal, 10)
                .frame(height: PanelMetrics.actionRowHeight)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(index == model.actionSelection ? Color.primary.opacity(0.1) : .clear)
                )
                .contentShape(Rectangle())
                .onTapGesture { model.runAction(at: index) }
                .onHover { if $0 { model.actionSelection = index } }
            }
        }
        .padding(6)
        .frame(width: 270)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
    }
}

// MARK: - Small pieces

private struct KeyChip: View {
    let keys: String
    let type: Typography

    var body: some View {
        Text(keys)
            .font(type.captionStrong)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 18)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
    }
}

private struct FooterButton: View {
    let label: String
    let keys: String
    let type: Typography
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label).font(type.caption).foregroundStyle(.secondary)
                KeyChip(keys: keys, type: type)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct Hairline: View {
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
    }
}

/// Fades the list out at its top and bottom edges instead of a hard cut.
private struct EdgeFade: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 6)
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 14)
        }
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
