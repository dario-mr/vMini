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

        XCTAssertTrue(palette.appBackground.isEqual(NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.13, alpha: 1.0)))
        XCTAssertTrue(palette.windowBackground.isEqual(NSColor(calibratedRed: 0.11, green: 0.14, blue: 0.17, alpha: 1.0)))
        XCTAssertTrue(palette.editorBackground.isEqual(NSColor(calibratedRed: 0.08, green: 0.16, blue: 0.20, alpha: 1.0)))
        XCTAssertTrue(palette.tabBarBackground.isEqual(NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.28, alpha: 1.0)))
        XCTAssertTrue(palette.primaryText.isEqual(NSColor(white: 0.98, alpha: 1.0)))
        XCTAssertTrue(palette.primaryActionBackground.isEqual(NSColor(calibratedRed: 0.23, green: 0.46, blue: 0.72, alpha: 1.0)))
        XCTAssertTrue(palette.syntaxHeadingText.isEqual(NSColor(calibratedRed: 0.98, green: 0.69, blue: 0.72, alpha: 1.0)))
        XCTAssertTrue(palette.syntaxCodeBlockBackground.isEqual(NSColor(white: 1.0, alpha: 0.08)))
    }

    func testSyntaxThemeIsDerivedFromThemePalette() {
        let palette = ThemeCatalog.palette(for: .default)
        let syntaxTheme = palette.syntaxTheme

        XCTAssertTrue(syntaxTheme.plainText.isEqual(palette.primaryText))
        XCTAssertTrue(syntaxTheme.codeFence.isEqual(palette.syntaxCodeFence))
        XCTAssertTrue(syntaxTheme.codeBlockBackground.isEqual(palette.syntaxCodeBlockBackground))
        XCTAssertTrue(syntaxTheme.linkURL.isEqual(palette.syntaxLinkURL))
        XCTAssertTrue(syntaxTheme.keyword.isEqual(palette.syntaxKeyword))
        XCTAssertTrue(syntaxTheme.comment.isEqual(palette.syntaxComment))
        XCTAssertTrue(syntaxTheme.propertyKey.isEqual(palette.syntaxPropertyKey))
    }

    func testAbsolutelyThemeMatchesCodexAnchors() {
        let palette = ThemeCatalog.palette(for: .absolutely)

        XCTAssertTrue(palette.windowBackground.isEqual(NSColor(calibratedRed: 45.0 / 255.0, green: 45.0 / 255.0, blue: 43.0 / 255.0, alpha: 1.0)))
        XCTAssertTrue(palette.editorBackground.isEqual(NSColor(calibratedRed: 36.0 / 255.0, green: 36.0 / 255.0, blue: 35.0 / 255.0, alpha: 1.0)))
        XCTAssertTrue(palette.primaryText.isEqual(NSColor(calibratedRed: 249.0 / 255.0, green: 249.0 / 255.0, blue: 247.0 / 255.0, alpha: 1.0)))
        XCTAssertTrue(palette.primaryActionBackground.isEqual(NSColor(calibratedRed: 204.0 / 255.0, green: 125.0 / 255.0, blue: 94.0 / 255.0, alpha: 1.0)))
        XCTAssertTrue(palette.syntaxHeadingMarker.isEqual(NSColor(calibratedRed: 204.0 / 255.0, green: 125.0 / 255.0, blue: 94.0 / 255.0, alpha: 1.0)))
        XCTAssertTrue(palette.syntaxHeadingText.isEqual(NSColor(calibratedRed: 232.0 / 255.0, green: 165.0 / 255.0, blue: 139.0 / 255.0, alpha: 1.0)))
        XCTAssertTrue(palette.syntaxLinkURL.isEqual(NSColor(calibratedRed: 0.0, green: 200.0 / 255.0, blue: 83.0 / 255.0, alpha: 1.0)))
    }

    func testDraculaThemeMatchesOfficialPalette() {
        let palette = ThemeCatalog.palette(for: .dracula)

        XCTAssertTrue(palette.windowBackground.isEqual(NSColor(calibratedRed: 40.0 / 255.0, green: 42.0 / 255.0, blue: 54.0 / 255.0, alpha: 1.0)))
        XCTAssertTrue(palette.editorBackground.isEqual(NSColor(calibratedRed: 40.0 / 255.0, green: 42.0 / 255.0, blue: 54.0 / 255.0, alpha: 1.0)))
        XCTAssertTrue(palette.primaryText.isEqual(NSColor(calibratedRed: 248.0 / 255.0, green: 248.0 / 255.0, blue: 242.0 / 255.0, alpha: 1.0)))
        XCTAssertTrue(palette.primaryActionBackground.isEqual(NSColor(calibratedRed: 189.0 / 255.0, green: 147.0 / 255.0, blue: 249.0 / 255.0, alpha: 1.0)))
        XCTAssertTrue(palette.syntaxListMarker.isEqual(NSColor(calibratedRed: 255.0 / 255.0, green: 184.0 / 255.0, blue: 108.0 / 255.0, alpha: 1.0)))
        XCTAssertTrue(palette.syntaxHeadingText.isEqual(NSColor(calibratedRed: 255.0 / 255.0, green: 179.0 / 255.0, blue: 218.0 / 255.0, alpha: 1.0)))
        XCTAssertTrue(palette.syntaxLinkURL.isEqual(NSColor(calibratedRed: 80.0 / 255.0, green: 250.0 / 255.0, blue: 123.0 / 255.0, alpha: 1.0)))
        XCTAssertTrue(palette.syntaxComment.isEqual(NSColor(calibratedRed: 139.0 / 255.0, green: 146.0 / 255.0, blue: 178.0 / 255.0, alpha: 1.0)))
        XCTAssertTrue(palette.syntaxBuiltin.isEqual(NSColor(calibratedRed: 255.0 / 255.0, green: 184.0 / 255.0, blue: 108.0 / 255.0, alpha: 1.0)))
        XCTAssertTrue(palette.syntaxPropertyKey.isEqual(NSColor(calibratedRed: 139.0 / 255.0, green: 233.0 / 255.0, blue: 253.0 / 255.0, alpha: 1.0)))
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "ThemeSystemTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}
