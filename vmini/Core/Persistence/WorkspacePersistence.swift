import Foundation

@MainActor
final class WorkspacePersistence {
    static let shared = WorkspacePersistence()

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var workspaceWindowFrame: String? {
        get { userDefaults.string(forKey: UserDefaultsKeys.workspaceWindowFrame) }
        set { set(newValue, forKey: UserDefaultsKeys.workspaceWindowFrame) }
    }

    var openFilesSidebarWidth: Double {
        get { userDefaults.double(forKey: UserDefaultsKeys.openFilesSidebarWidth) }
        set { userDefaults.set(newValue, forKey: UserDefaultsKeys.openFilesSidebarWidth) }
    }

    var openFolderBookmarks: [Data] {
        get { userDefaults.array(forKey: UserDefaultsKeys.openFolders) as? [Data] ?? [] }
        set { userDefaults.set(newValue, forKey: UserDefaultsKeys.openFolders) }
    }

    var openFolderExpandedPaths: [String] {
        get { userDefaults.stringArray(forKey: UserDefaultsKeys.openFoldersExpandedPaths) ?? [] }
        set { userDefaults.set(newValue, forKey: UserDefaultsKeys.openFoldersExpandedPaths) }
    }

    var sessionDocumentReferencesData: Data? {
        get { userDefaults.data(forKey: UserDefaultsKeys.sessionRestorerDocumentReferences) }
        set { set(newValue, forKey: UserDefaultsKeys.sessionRestorerDocumentReferences) }
    }

    var sessionActiveDocumentReferenceData: Data? {
        get { userDefaults.data(forKey: UserDefaultsKeys.sessionRestorerActiveDocumentReference) }
        set { set(newValue, forKey: UserDefaultsKeys.sessionRestorerActiveDocumentReference) }
    }

    var syntaxLanguageOverrides: [String: String] {
        get { userDefaults.dictionary(forKey: UserDefaultsKeys.syntaxLanguageOverrides) as? [String: String] ?? [:] }
        set { userDefaults.set(newValue, forKey: UserDefaultsKeys.syntaxLanguageOverrides) }
    }

    private func set(_ value: Any?, forKey key: String) {
        if let value {
            userDefaults.set(value, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }
}
