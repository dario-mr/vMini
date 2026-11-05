import Foundation

final class MarkdownTableCache {
    private(set) var tables: [MarkdownTable] = []
    private(set) var highlightRange = NSRange(location: 0, length: 0)
    private(set) var revision: UInt64 = 0
    private var source: NSString = ""
    private var fences: MarkdownSyntaxHighlighter.FenceCache?
    private var htmlBlocks: [NSRange] = []

    func reset(_ text: NSString, enabled: Bool) {
        // NSTextStorage can supply mutable NSString backing; keep the previous revision immutable.
        source = text.copy() as! NSString
        highlightRange = NSRange(location: 0, length: text.length)
        fences = enabled ? MarkdownFenceCache.makeFenceCache(in: text) : nil
        htmlBlocks = enabled ? MarkdownHTMLBlocks.ranges(in: text) : []
        tables = enabled ? MarkdownTableParser.parse(text, excluding: fences!.blocks.map(\.totalRange) + htmlBlocks) : []
        revision &+= 1
    }

    func update(_ text: NSString, edit: SyntaxHighlightEditContext?) {
        guard let edit,
              edit.replacementRange.upperBound <= source.length,
              source.substring(with: edit.replacementRange) == edit.replacedText,
              text.length == source.length - edit.replacementRange.length + (edit.replacementString as NSString).length else {
            reset(text, enabled: true)
            return
        }
        let previousTables = tables
        let delta = text.length - source.length
        defer {
            // Cell edits do not change styles in the rest of a table when its boundaries stay intact.
            if !edit.replacedText.contains(where: \.isNewline), !edit.replacementString.contains(where: \.isNewline),
               previousTables.count == tables.count,
               zip(previousTables, tables).allSatisfy({ old, new in
                   let moved = old.range.location >= edit.replacementRange.upperBound
                   let affected = old.range.intersects(edit.replacementRange)
                       || NSLocationInRange(edit.replacementRange.location, old.range)
                   let mapped = NSRange(location: old.range.location + (moved ? delta : 0),
                                        length: old.range.length + (affected ? delta : 0))
                   return mapped == new.range && old.alignments == new.alignments
               }) {
                highlightRange = NSRange(location: 0, length: 0)
            }
        }
        guard let fences,
              !htmlBlocks.contains(where: { $0.location <= edit.replacementRange.upperBound && edit.replacementRange.location <= $0.upperBound }),
              !source.substring(with: source.lineRange(for: edit.replacementRange)).contains("<"),
              !text.substring(with: text.lineRange(for: NSRange(location: edit.replacementRange.location,
                  length: (edit.replacementString as NSString).length))).contains("<"),
              !MarkdownFenceCache.isFenceSensitiveEdit(
                editedRange: NSRange(location: edit.replacementRange.location, length: (edit.replacementString as NSString).length),
                editContext: edit, in: text),
              let fenceUpdate = MarkdownFenceCache.updateFenceCache(fences, editContext: edit, in: text) else {
            reset(text, enabled: true)
            return
        }
        htmlBlocks = htmlBlocks.map {
            NSRange(location: $0.location >= edit.replacementRange.upperBound ? $0.location + delta : $0.location,
                    length: $0.length)
        }
        let oldRange = MarkdownTableParser.blockRange(around: edit.replacementRange, in: source)
        let mappedRange = NSRange(location: oldRange.location, length: oldRange.length + delta)
        let changedRange = NSRange(location: edit.replacementRange.location, length: (edit.replacementString as NSString).length)
        highlightRange = NSUnionRange(mappedRange, MarkdownTableParser.blockRange(around: changedRange, in: text))
            .clamped(toLength: text.length)
        // Include blocks joined by deleting a blank line, before retaining cached tables outside the scan.
        highlightRange = MarkdownTableParser.blockRange(around: highlightRange, in: text)
        let retained = tables.compactMap { table -> MarkdownTable? in
            guard !table.range.intersects(oldRange) else { return nil }
            let shifted = table.range.location >= oldRange.upperBound ? table.shifted(by: delta) : table
            return shifted.range.intersects(highlightRange) ? nil : shifted
        }
        tables = (retained + MarkdownTableParser.parse(text, in: highlightRange,
                    excluding: fenceUpdate.cache.blocks.map(\.totalRange) + htmlBlocks)).sorted { $0.range.location < $1.range.location }
        self.fences = fenceUpdate.cache
        source = text.copy() as! NSString
        revision &+= 1
    }
}
