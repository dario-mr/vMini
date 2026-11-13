import AppKit

@MainActor
enum EditorStatusBarStateBuilder {
    static func makeState(document: Document?, cursorPosition: EditorCursorPosition?) -> EditorStatusBarState? {
        guard let document else {
            return nil
        }

        let hasOverride = document.hasSyntaxLanguageOverride
        let autoDetectedSyntaxLanguage = document.autoDetectedSyntaxLanguage
        let selectedSyntaxLanguage = hasOverride ? document.syntaxLanguage : autoDetectedSyntaxLanguage

        return EditorStatusBarState(
            title: hasOverride ? selectedSyntaxLanguage.displayName : "\(selectedSyntaxLanguage.displayName) (Auto)",
            autoDetectedSyntaxLanguage: autoDetectedSyntaxLanguage,
            selectedSyntaxLanguage: selectedSyntaxLanguage,
            hasOverride: hasOverride,
            cursorPosition: cursorPosition ?? EditorCursorPosition(line: 1, column: 1)
        )
    }
}
