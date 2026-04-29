import AppKit
import Foundation
import UniformTypeIdentifiers

final class DocumentController: NSDocumentController {
    override func beginOpenPanel(
        _ openPanel: NSOpenPanel,
        forTypes inTypes: [String]?,
        completionHandler: @escaping (Int) -> Void
    ) {
        openPanel.showsHiddenFiles = true
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false

        super.beginOpenPanel(openPanel, forTypes: nil, completionHandler: completionHandler)
    }

    override func typeForContents(of url: URL) throws -> String {
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

        let inferredTypeIdentifier = try? super.typeForContents(of: url)

        if
            let inferredTypeIdentifier,
            let inferredType = UTType(inferredTypeIdentifier),
            Document.supportedTypes.contains(where: { inferredType.conforms(to: $0) })
        {
            return inferredTypeIdentifier
        }

        if looksLikeTextFile(at: url) {
            return UTType.plainText.identifier
        }

        if let inferredTypeIdentifier {
            return inferredTypeIdentifier
        }

        return UTType.plainText.identifier
    }

    private func looksLikeTextFile(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: 4096) else {
            return false
        }

        if data.contains(0) {
            return false
        }

        let encodings: [String.Encoding] = [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .ascii]
        return encodings.contains { String(data: data, encoding: $0) != nil }
    }
}
