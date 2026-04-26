import AppKit
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
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return false
        }

        let sample = data.prefix(4096)
        if sample.contains(0) {
            return false
        }

        let encodings: [String.Encoding] = [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .ascii]
        return encodings.contains { String(data: sample, encoding: $0) != nil }
    }
}
