import Foundation

enum RestorableDocumentReference: Codable, Equatable {
    case file(path: String)
    case untitled(sessionID: UUID)

    var persistenceIdentifier: String {
        switch self {
        case .file(let path):
            URL(fileURLWithPath: path).standardizedFileURL.path
        case .untitled(let sessionID):
            "untitled:\(sessionID.uuidString.lowercased())"
        }
    }
}
