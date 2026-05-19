import AppKit

struct SyntaxThemePalette {
    let headingMarker: NSColor
    let headingText: NSColor
    let listMarker: NSColor
    let blockquoteMarker: NSColor
    let inlineCode: NSColor
    let codeFence: NSColor
    let codeBlockBackground: NSColor
    let linkText: NSColor
    let linkURL: NSColor
    let emphasisMarker: NSColor
    let thematicBreak: NSColor
    let comment: NSColor
    let string: NSColor
    let variable: NSColor
    let keyword: NSColor
    let `operator`: NSColor
    let builtin: NSColor
    let option: NSColor
    let propertyKey: NSColor

    func makeSyntaxTheme(plainText: NSColor) -> SyntaxTheme {
        SyntaxTheme(
            plainText: plainText,
            headingMarker: headingMarker,
            headingText: headingText,
            listMarker: listMarker,
            blockquoteMarker: blockquoteMarker,
            inlineCode: inlineCode,
            codeFence: codeFence,
            codeBlockBackground: codeBlockBackground,
            linkText: linkText,
            linkURL: linkURL,
            emphasisMarker: emphasisMarker,
            thematicBreak: thematicBreak,
            comment: comment,
            string: string,
            variable: variable,
            keyword: keyword,
            operator: self.operator,
            builtin: builtin,
            option: option,
            propertyKey: propertyKey
        )
    }
}
