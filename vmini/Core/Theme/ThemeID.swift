import AppKit

enum ThemeID: String, CaseIterable {
    case `default` = "default"
    case absolutely = "absolutely"
    case dracula = "dracula"
    case gruvboxDark = "gruvbox-dark"
    case solarizedLight = "solarized-light"
    case nord = "nord"
    case catppuccinMocha = "catppuccin-mocha"

    var displayName: String {
        switch self {
        case .default:
            "Slate"
        case .absolutely:
            "Absolutely"
        case .dracula:
            "Dracula"
        case .gruvboxDark:
            "Gruvbox Dark"
        case .solarizedLight:
            "Solarized Light"
        case .nord:
            "Nord"
        case .catppuccinMocha:
            "Catppuccin Mocha"
        }
    }

    var preferredAppearance: NSAppearance.Name {
        switch self {
        case .solarizedLight:
            .aqua
        default:
            .darkAqua
        }
    }
}
