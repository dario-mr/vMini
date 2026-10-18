import Foundation

struct MarkdownLink {
    let textRange: NSRange
    let urlRange: NSRange
    let destination: String

    // shortcut: inline links only, add reference-link resolution when reference links are supported.
    static func tokens(in line: String, offset: Int) -> [MarkdownLink] {
        let text = line as NSString
        var links: [MarkdownLink] = []
        var index = 0
        while index < text.length {
            let opening = text.range(of: "[", range: NSRange(location: index, length: text.length - index))
            guard opening.location != NSNotFound else { break }
            index = opening.location + 1
            let closing = text.range(of: "](", range: NSRange(location: index, length: text.length - index))
            guard closing.location != NSNotFound else { continue }
            let label = text.substring(with: NSRange(location: index, length: closing.location - index))
            guard !label.contains("["), !label.contains("]") else { continue }
            let destinationStart = closing.upperBound
            var end = destinationStart
            var depth = 1
            while end < text.length {
                let character = text.substring(with: NSRange(location: end, length: 1))
                if character == "\\" {
                    end += 2
                    continue
                }
                if character == "(" { depth += 1 }
                if character == ")" { depth -= 1 }
                if depth == 0 { break }
                end += 1
            }
            guard depth == 0 else { continue }
            let preceding = opening.location > 0 ? text.substring(with: NSRange(location: opening.location - 1, length: 1)) : ""
            if preceding != "!", preceding != "\\" {
                links.append(MarkdownLink(
                    textRange: NSRange(location: offset + opening.location, length: closing.location - opening.location + 1),
                    urlRange: NSRange(location: offset + closing.location + 1, length: end - closing.location),
                    destination: text.substring(with: NSRange(location: destinationStart, length: end - destinationStart))
                ))
            }
            index = end + 1
        }
        return links
    }

    static func destination(in source: String, at index: Int) -> String? {
        let text = source as NSString
        guard index >= 0, index < text.length else { return nil }
        let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
        let line = text.substring(with: lineRange)
        guard let link = tokens(in: line, offset: lineRange.location).first(where: {
            index > $0.textRange.location && index < $0.textRange.upperBound - 1
        }), !MarkdownLineStylePlanner.inlineCodeRanges(in: line, offset: lineRange.location).contains(where: {
            $0.intersects(link.textRange)
        }), !MarkdownFenceCache.makeFenceCache(in: text).blocks.contains(where: {
            NSLocationInRange(index, $0.totalRange)
        }) else { return nil }
        return link.destination
    }

    static func resolve(_ destination: String, relativeTo documentURL: URL?) -> URL? {
        var destination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        if destination.hasPrefix("<"), destination.hasSuffix(">") {
            destination = String(destination.dropFirst().dropLast())
        }
        guard !destination.isEmpty, !destination.hasPrefix("#"),
              let url = URL(string: destination) else { return nil }
        if let scheme = url.scheme?.lowercased() {
            return ["http", "https", "file"].contains(scheme) ? url : nil
        }
        guard destination.hasPrefix("/") || documentURL != nil else { return nil }
        guard let resolved = URL(string: destination, relativeTo: documentURL?.deletingLastPathComponent()),
              let components = URLComponents(url: resolved.absoluteURL, resolvingAgainstBaseURL: true) else { return nil }
        return URL(fileURLWithPath: components.path).standardizedFileURL
    }
}
