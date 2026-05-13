import AppKit

enum EditorFontID: String, CaseIterable {
    case systemMonospaced
    case sfMono
    case menlo
    case monaco
    case andaleMono
    case courierNew
    case jetBrainsMono
    case firaCode
    case ibmPlexMono
    case sourceCodePro
    case robotoMono
    case ptMono

    static let fallback: EditorFontID = .systemMonospaced

    private enum Kind {
        case systemMonospaced
        case namedFont(String)
    }

    var displayName: String {
        metadata.displayName
    }

    var isSystemMonospaced: Bool {
        if case .systemMonospaced = metadata.kind {
            true
        } else {
            false
        }
    }

    var postScriptName: String? {
        guard case let .namedFont(name) = metadata.kind else {
            return nil
        }

        return name
    }

    private var metadata: (displayName: String, kind: Kind) {
        switch self {
        case .systemMonospaced:
            ("System Monospaced", .systemMonospaced)
        case .sfMono:
            ("SF Mono", .namedFont("SFMono-Regular"))
        case .menlo:
            ("Menlo", .namedFont("Menlo-Regular"))
        case .monaco:
            ("Monaco", .namedFont("Monaco"))
        case .andaleMono:
            ("Andale Mono", .namedFont("Andale Mono"))
        case .courierNew:
            ("Courier New", .namedFont("Courier New"))
        case .jetBrainsMono:
            ("JetBrains Mono", .namedFont("JetBrainsMono-Regular"))
        case .firaCode:
            ("Fira Code", .namedFont("FiraCode-Regular"))
        case .ibmPlexMono:
            ("IBM Plex Mono", .namedFont("IBMPlexMono-Regular"))
        case .sourceCodePro:
            ("Source Code Pro", .namedFont("SourceCodePro-Regular"))
        case .robotoMono:
            ("Roboto Mono", .namedFont("RobotoMono-Regular"))
        case .ptMono:
            ("PT Mono", .namedFont("PTMono-Regular"))
        }
    }
}

struct EditorFontResolver {
    static func availableFontIDs() -> [EditorFontID] {
        EditorFontID.allCases.filter(isAvailable(_:))
    }

    static func isAvailable(_ fontID: EditorFontID) -> Bool {
        if fontID.isSystemMonospaced {
            true
        } else if let postScriptName = fontID.postScriptName {
            namedFont(postScriptName, size: 13) != nil
        } else {
            false
        }
    }

    static func font(for fontID: EditorFontID, size: CGFloat) -> NSFont {
        if fontID.isSystemMonospaced {
            NSFont.monospacedSystemFont(ofSize: size, weight: .light)
        } else if let postScriptName = fontID.postScriptName {
            namedFont(postScriptName, size: size) ?? fallbackFont(size: size)
        } else {
            fallbackFont(size: size)
        }
    }

    private static func fallbackFont(size: CGFloat) -> NSFont {
        font(for: .systemMonospaced, size: size)
    }

    private static func namedFont(_ name: String, size: CGFloat) -> NSFont? {
        NSFont(name: name, size: size)
    }
}
