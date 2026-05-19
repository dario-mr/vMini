import AppKit
import XCTest
@testable import vmini

@MainActor
final class ThemeSystemTests: XCTestCase {
    func testThemeStoreDefaultsToDefaultTheme() {
        let store = ThemeStore(userDefaults: makeUserDefaults())
        XCTAssertEqual(store.currentThemeID(), .default)
    }

    func testThemeStoreReloadsValidThemeID() {
        let userDefaults = makeUserDefaults()
        userDefaults.set(ThemeID.absolutely.rawValue, forKey: UserDefaultsKeys.themeID)

        let store = ThemeStore(userDefaults: userDefaults)
        XCTAssertEqual(store.currentThemeID(), .absolutely)
    }

    func testThemeStoreFallsBackForInvalidThemeID() {
        let userDefaults = makeUserDefaults()
        userDefaults.set("unknown-theme", forKey: UserDefaultsKeys.themeID)

        let store = ThemeStore(userDefaults: userDefaults)
        XCTAssertEqual(store.currentThemeID(), .default)
    }

    func testDefaultThemeMatchesCurrentPalette() {
        let palette = ThemeCatalog.palette(for: .default)

        assertColor(palette.appBackground, matchesHex: 0x141C21)
        assertColor(palette.windowBackground, matchesHex: 0x1C242B)
        assertColor(palette.editorBackground, matchesHex: 0x142933)
        assertColor(palette.tabBarBackground, matchesHex: 0x333D47)
        assertColor(palette.primaryText, matchesHex: 0xFAFAFA)
        assertColor(palette.primaryActionBackground, matchesHex: 0x3B75B8)
        assertColor(palette.syntaxPalette.headingText, matchesHex: 0xFAB0B8)
        assertColor(palette.syntaxPalette.codeBlockBackground, matchesHex: 0xFFFFFF, alpha: 0.08)
    }

    func testSyntaxThemeIsDerivedFromThemePalette() {
        let palette = ThemeCatalog.palette(for: .default)
        let syntaxTheme = palette.syntaxTheme

        XCTAssertTrue(syntaxTheme.plainText.isEqual(palette.primaryText))
        XCTAssertTrue(syntaxTheme.codeFence.isEqual(palette.syntaxPalette.codeFence))
        XCTAssertTrue(syntaxTheme.codeBlockBackground.isEqual(palette.syntaxPalette.codeBlockBackground))
        XCTAssertTrue(syntaxTheme.linkURL.isEqual(palette.syntaxPalette.linkURL))
        XCTAssertTrue(syntaxTheme.keyword.isEqual(palette.syntaxPalette.keyword))
        XCTAssertTrue(syntaxTheme.comment.isEqual(palette.syntaxPalette.comment))
        XCTAssertTrue(syntaxTheme.option.isEqual(palette.syntaxPalette.option))
        XCTAssertTrue(syntaxTheme.propertyKey.isEqual(palette.syntaxPalette.propertyKey))
    }

    func testAbsolutelyThemeMatchesCodexAnchors() {
        let palette = ThemeCatalog.palette(for: .absolutely)

        assertColor(palette.windowBackground, matchesHex: 0x2D2D2B)
        assertColor(palette.editorBackground, matchesHex: 0x242423)
        assertColor(palette.primaryText, matchesHex: 0xF9F9F7)
        assertColor(palette.primaryActionBackground, matchesHex: 0xCC7D5E)
        assertColor(palette.syntaxPalette.headingMarker, matchesHex: 0xCC7D5E)
        assertColor(palette.syntaxPalette.headingText, matchesHex: 0xE8A58B)
        assertColor(palette.syntaxPalette.linkURL, matchesHex: 0x00C853)
        assertColor(palette.syntaxPalette.propertyKey, matchesHex: 0xCC7D5E)
    }

    func testDraculaThemeMatchesOfficialPalette() {
        let palette = ThemeCatalog.palette(for: .dracula)

        assertColor(palette.windowBackground, matchesHex: 0x282A36)
        assertColor(palette.editorBackground, matchesHex: 0x282A36)
        assertColor(palette.primaryText, matchesHex: 0xF8F8F2)
        assertColor(palette.primaryActionBackground, matchesHex: 0xA277DE)
        assertColor(palette.syntaxPalette.listMarker, matchesHex: 0xFFB86C)
        assertColor(palette.syntaxPalette.headingText, matchesHex: 0xFFB3DA)
        assertColor(palette.syntaxPalette.linkURL, matchesHex: 0x50FA7B)
        assertColor(palette.syntaxPalette.comment, matchesHex: 0x8B92B2)
        assertColor(palette.syntaxPalette.builtin, matchesHex: 0xFFB86C)
        assertColor(palette.syntaxPalette.propertyKey, matchesHex: 0x8BE9FD)
    }

    func testGruvboxDarkThemeMatchesOfficialPalette() {
        let palette = ThemeCatalog.palette(for: .gruvboxDark)

        assertColor(palette.windowBackground, matchesHex: 0x282828)
        assertColor(palette.editorBackground, matchesHex: 0x282828)
        assertColor(palette.primaryText, matchesHex: 0xEBDBB2)
        assertColor(palette.primaryActionBackground, matchesHex: 0x458588)
        assertColor(palette.syntaxPalette.keyword, matchesHex: 0xFB4934)
        assertColor(palette.syntaxPalette.string, matchesHex: 0xB8BB26)
        assertColor(palette.syntaxPalette.builtin, matchesHex: 0xFE8019)
        assertColor(palette.syntaxPalette.propertyKey, matchesHex: 0x83A598)
    }

    func testSolarizedLightThemeMatchesOfficialPalette() {
        let palette = ThemeCatalog.palette(for: .solarizedLight)

        assertColor(palette.windowBackground, matchesHex: 0xEEE8D5)
        assertColor(palette.editorBackground, matchesHex: 0xFDF6E3)
        assertColor(palette.primaryText, matchesHex: 0x586E75)
        assertColor(palette.primaryActionBackground, matchesHex: 0x268BD2)
        assertColor(palette.syntaxPalette.keyword, matchesHex: 0x268BD2)
        assertColor(palette.syntaxPalette.string, matchesHex: 0x859900)
        assertColor(palette.syntaxPalette.builtin, matchesHex: 0xCB4B16)
        assertColor(palette.syntaxPalette.propertyKey, matchesHex: 0xCB4B16)
    }

    func testNordThemeMatchesOfficialPalette() {
        let palette = ThemeCatalog.palette(for: .nord)

        assertColor(palette.windowBackground, matchesHex: 0x2E3440)
        assertColor(palette.editorBackground, matchesHex: 0x2E3440)
        assertColor(palette.primaryText, matchesHex: 0xECEFF4)
        assertColor(palette.primaryActionBackground, matchesHex: 0x5E81AC)
        assertColor(palette.syntaxPalette.keyword, matchesHex: 0x81A1C1)
        assertColor(palette.syntaxPalette.string, matchesHex: 0xA3BE8C)
        assertColor(palette.syntaxPalette.builtin, matchesHex: 0xD08770)
        assertColor(palette.syntaxPalette.propertyKey, matchesHex: 0x81A1C1)
    }

    func testCatppuccinMochaThemeMatchesOfficialPalette() {
        let palette = ThemeCatalog.palette(for: .catppuccinMocha)

        assertColor(palette.windowBackground, matchesHex: 0x181825)
        assertColor(palette.editorBackground, matchesHex: 0x1E1E2E)
        assertColor(palette.primaryText, matchesHex: 0xCDD6F4)
        assertColor(palette.primaryActionBackground, matchesHex: 0xCBA6F7)
        assertColor(palette.syntaxPalette.keyword, matchesHex: 0xCBA6F7)
        assertColor(palette.syntaxPalette.string, matchesHex: 0xA6E3A1)
        assertColor(palette.syntaxPalette.builtin, matchesHex: 0xFAB387)
        assertColor(palette.syntaxPalette.propertyKey, matchesHex: 0x89DCEB)
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "ThemeSystemTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }

    private func assertColor(
        _ actualColor: NSColor,
        matchesHex hex: Int,
        alpha: CGFloat = 1.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expected = NSColor(hex: hex, alpha: alpha)
        XCTAssertTrue(actualColor.isEqual(expected), file: file, line: line)
    }
}
