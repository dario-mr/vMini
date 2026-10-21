import Foundation

enum WebLink {
    private static let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func matches(in text: String, range: NSRange) -> [NSTextCheckingResult] {
        detector.matches(in: text, range: range).filter {
            guard let scheme = $0.url?.scheme?.lowercased() else { return false }
            return scheme == "http" || scheme == "https"
        }
    }

    static func url(in source: String, at index: Int) -> URL? {
        let text = source as NSString
        guard index >= 0, index < text.length else { return nil }
        let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
        return matches(in: source, range: lineRange).first {
            NSLocationInRange(index, $0.range)
        }?.url
    }
}
