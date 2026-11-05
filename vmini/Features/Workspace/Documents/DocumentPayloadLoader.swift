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

    init(url: URL, typeName: String, content: Content) {
        self.url = url
        self.typeName = typeName
        self.content = content
    }

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
        if
            let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
            Document.supportedTypes.contains(where: { contentType.conforms(to: $0) })
        {
            return contentType.identifier
        }

        if
            let inferredType = UTType(filenameExtension: url.pathExtension),
            Document.supportedTypes.contains(where: { inferredType.conforms(to: $0) })
        {
            return inferredType.identifier
        }

        return UTType.plainText.identifier
    }
}
