import Foundation
import SwiftTreeSitter

enum MarkdownHTMLBlocks {
    private static let language = TreeSitterSyntaxGrammar.definition(for: .markdown)!.language
    private static let query = try! Query(language: language, data: Data("(html_block) @html".utf8))

    static func ranges(in text: NSString) -> [NSRange] {
        guard text.range(of: "<", options: .literal).location != NSNotFound else { return [] }
        let parser = Parser()
        try! parser.setLanguage(language)
        guard let tree = TreeSitterSyntaxParser.parse(parser, oldTree: nil, source: text) else { return [] }
        return ranges(in: tree)
    }

    static func ranges(in tree: MutableTree) -> [NSRange] {
        return query.execute(in: tree).flatMap { $0.captures.map(\.range) }
    }
}
