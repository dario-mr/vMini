import AppKit

final class MarkdownTableLayoutCache {
    final class Layout {
        let columns: MarkdownTableColumnLayout?
        let separators: [MarkdownTableRendering.Separator]

        init(table: MarkdownTable, layoutManager: NSLayoutManager) {
            columns = MarkdownTableColumnLayout(table: table, layoutManager: layoutManager)
            separators = MarkdownTableRendering.separators(for: table, layoutManager: layoutManager)
        }
    }

    private var layouts: [NSRange: Layout] = [:]

    func layout(for table: MarkdownTable, layoutManager: NSLayoutManager) -> Layout {
        if let cached = layouts[table.range] { return cached }
        let layout = Layout(table: table, layoutManager: layoutManager)
        layouts[table.range] = layout
        return layout
    }

    func invalidate() { layouts.removeAll() }
}
