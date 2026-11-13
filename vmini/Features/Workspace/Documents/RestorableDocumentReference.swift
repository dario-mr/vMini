import Foundation

enum RestorableDocumentReference: Codable, Equatable {
    case file(path: String)
    case untitled(sessionID: UUID)

    init(fileURL: URL?, sessionIdentifier: UUID) {
        if let fileURL {
            self = .file(path: fileURL.standardizedFileURL.path)
        } else {
            self = .untitled(sessionID: sessionIdentifier)
        }
    }

    var persistenceIdentifier: String {
        switch self {
        case .file(let path):
            URL(fileURLWithPath: path).standardizedFileURL.path
        case .untitled(let sessionID):
            "untitled:\(sessionID.uuidString.lowercased())"
        }
    }
}
