import AppKit

@MainActor
final class DocumentContentController {
    private(set) var text = ""
    private(set) var typeIdentifier: String?
    private let syntaxOverrideStore: SyntaxOverrideStore
    private var syntaxLanguageOverride: SyntaxLanguage?

    init(syntaxOverrideStore: SyntaxOverrideStore) {
        self.syntaxOverrideStore = syntaxOverrideStore
    }

    convenience init() {
        self.init(syntaxOverrideStore: .shared)
    }

    func currentText(editorText: String?) -> String {
        editorText ?? text
    }

    func updateRead(typeName: String, text: String) {
        typeIdentifier = typeName
        self.text = text
    }

    func updateText(_ text: String) {
        self.text = text
    }

    func applyFileURLChange(from oldValue: URL?, to newValue: URL?) {
        guard newValue != oldValue else { return }

        if let newValue {
            let newIdentifier = Self.persistenceIdentifier(for: newValue)
            if let oldValue {
                syntaxOverrideStore.migrateOverride(
                    from: Self.persistenceIdentifier(for: oldValue),
                    to: newIdentifier,
                    currentOverride: syntaxLanguageOverride
                )
            } else if let syntaxLanguageOverride {
                syntaxOverrideStore.setOverride(syntaxLanguageOverride, for: newIdentifier)
            } else {
                syntaxLanguageOverride = syntaxOverrideStore.override(for: newIdentifier)
            }
        }
    }

    func autoDetectedSyntaxLanguage(fileURL: URL?, sampleText: String) -> SyntaxLanguage {
        SyntaxLanguageResolver.resolve(
            fileURL: fileURL,
            typeIdentifier: typeIdentifier,
            content: sampleText
        )
    }

    func syntaxLanguage(fileURL: URL?, sampleText: String) -> SyntaxLanguage {
        syntaxLanguageOverride ?? autoDetectedSyntaxLanguage(fileURL: fileURL, sampleText: sampleText)
    }

    var hasSyntaxLanguageOverride: Bool {
        syntaxLanguageOverride != nil
    }

    func syntaxOverrideMenuTitle(fileURL: URL?, sampleText: String) -> String {
        let resolvedSyntaxLanguage = syntaxLanguage(fileURL: fileURL, sampleText: sampleText)
        if hasSyntaxLanguageOverride {
            return resolvedSyntaxLanguage.displayName
        }

        return "\(resolvedSyntaxLanguage.displayName) (Auto)"
    }

    func setSyntaxLanguageOverride(_ language: SyntaxLanguage?, persistenceIdentifier: String?) {
        guard syntaxLanguageOverride != language else { return }
        syntaxLanguageOverride = language
        if let persistenceIdentifier {
            syntaxOverrideStore.setOverride(language, for: persistenceIdentifier)
        }
    }

    private static func persistenceIdentifier(for fileURL: URL) -> String {
        fileURL.standardizedFileURL.path
    }
}
