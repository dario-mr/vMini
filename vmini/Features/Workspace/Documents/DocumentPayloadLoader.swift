import AppKit
import UniformTypeIdentifiers

struct DocumentPayload: Sendable {
    let url: URL
    let typeName: String
    let text: String
}

enum DocumentPayloadLoader {
    static func load(from url: URL) async throws -> DocumentPayload {
        try await Task.detached(priority: .userInitiated) {
            let url = url.standardizedFileURL
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
