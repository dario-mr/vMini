enum ThemeCatalog {
    static func palette(for themeID: ThemeID) -> ThemePalette {
        switch themeID {
        case .default:
            defaultPalette
        case .absolutely:
            absolutelyPalette
        case .dracula:
            draculaPalette
        case .gruvboxDark:
            gruvboxDarkPalette
        case .solarizedLight:
            solarizedLightPalette
        case .nord:
            nordPalette
        case .catppuccinMocha:
            catppuccinMochaPalette
        }
    }
}
