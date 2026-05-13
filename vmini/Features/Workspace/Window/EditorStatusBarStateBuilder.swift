import AppKit

@MainActor
enum EditorStatusBarStateBuilder {
    static func makeState(document: Document?, cursorPosition: EditorCursorPosition?) -> EditorStatusBarState? {
        guard let document else {
            return nil
        }

        return EditorStatusBarState(
            title: document.syntaxOverrideMenuTitle,
            autoDetectedSyntaxLanguage: document.autoDetectedSyntaxLanguage,
            selectedSyntaxLanguage: document.syntaxLanguage,
            hasOverride: document.hasSyntaxLanguageOverride,
            cursorPosition: cursorPosition ?? EditorCursorPosition(line: 1, column: 1)
        )
    }
}
