import AppKit
import UniformTypeIdentifiers

struct DocumentPayload: Sendable {
    enum Content: Sendable {
        case text(String)
        case parquet
    }

    let url: URL
    let typeName: String
    let content: Content
}

extension DocumentPayload {
    init(url: URL, typeName: String, text: String) {
        self.init(url: url, typeName: typeName, content: .text(text))
    }
}

enum DocumentPayloadLoader {
    static func load(from url: URL) async throws -> DocumentPayload {
        try await Task.detached(priority: .userInitiated) {
            let url = url.standardizedFileURL
            if ParquetPage.recognizes(url) {
                return DocumentPayload(url: url, typeName: ParquetPage.typeIdentifier, content: .parquet)
            }
            let typeName = inferredType(for: url)
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard let text = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            return DocumentPayload(url: url, typeName: typeName, text: text)
        }.value
    }

    private nonisolated static func inferredType(for url: URL) -> String {
        supportedTypeIdentifier(for: url) ?? UTType.plainText.identifier
    }

    /// The file's own type, or the one its extension implies, when the editor can open it.
    nonisolated static func supportedTypeIdentifier(for url: URL) -> String? {
        let candidates = [
            try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
            UTType(filenameExtension: url.pathExtension),
        ]
        return candidates.compactMap { $0 }
            .first { type in Document.supportedTypes.contains(where: { type.conforms(to: $0) }) }?
            .identifier
    }
}
