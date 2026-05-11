import AppKit
import XCTest
@testable import vmini

@available(macOS 14.0, *)
@MainActor
final class EditorFontTests: XCTestCase {
    private nonisolated(unsafe) static var originalUserDefaults: UserDefaults?

    override func setUp() {
        super.setUp()
        let testUserDefaults = Self.makeUserDefaults()
        MainActor.assumeIsolated {
            Self.originalUserDefaults = EditorSettings.userDefaults
            EditorSettings.userDefaults = testUserDefaults
        }
    }

    override func tearDown() {
        if let originalUserDefaults = Self.originalUserDefaults {
            MainActor.assumeIsolated {
                EditorSettings.userDefaults = originalUserDefaults
            }
        }
        super.tearDown()
    }

    func testEditorSettingsDefaultsToFallbackFont() {
        XCTAssertEqual(EditorSettings.currentFontID(), .fallback)
    }

    func testEditorSettingsReloadsStoredFontWhenAvailable() throws {
        let storedFont = try XCTUnwrap(EditorFontResolver.availableFontIDs().last)

        EditorSettings.userDefaults.set(storedFont.rawValue, forKey: UserDefaultsKeys.editorFontID)

        XCTAssertEqual(EditorSettings.currentFontID(), storedFont)
    }

    func testEditorSettingsFallsBackForInvalidStoredFont() {
        EditorSettings.userDefaults.set("not-a-real-font-id", forKey: UserDefaultsKeys.editorFontID)

        XCTAssertEqual(EditorSettings.currentFontID(), .fallback)
    }

    func testResolverReturnsUsableFontForEveryCatalogEntry() {
        let fallbackFont = EditorFontResolver.font(for: .fallback, size: 15)

        for fontID in EditorFontID.allCases {
            let font = EditorFontResolver.font(for: fontID, size: 15)

            XCTAssertEqual(font.pointSize, 15, accuracy: 0.001)
            if !EditorFontResolver.isAvailable(fontID) {
                XCTAssertEqual(font.fontName, fallbackFont.fontName)
            }
        }
    }

    func testEditorViewControllerLoadsSavedFontAndRespondsToChanges() throws {
        let initialFont = try XCTUnwrap(EditorFontResolver.availableFontIDs().first)
        EditorSettings.setFontID(initialFont)

        let viewController = EditorViewController()
        viewController.loadViewIfNeeded()

        let textView = try XCTUnwrap(findTextView(in: viewController.view))
        XCTAssertEqual(textView.font?.fontName, EditorFontResolver.font(for: initialFont, size: EditorSettings.currentFontSize()).fontName)

        let alternateFont = EditorFontResolver.availableFontIDs().first(where: { $0 != initialFont }) ?? .fallback
        EditorSettings.setFontID(alternateFont)

        XCTAssertEqual(textView.font?.fontName, EditorFontResolver.font(for: alternateFont, size: EditorSettings.currentFontSize()).fontName)
        XCTAssertEqual(textView.textContainer?.widthTracksTextView, EditorSettings.isWordWrapEnabled())
    }

    func testFontSizeChangePreservesSyntaxHighlighting() throws {
        let viewController = EditorViewController()
        viewController.loadViewIfNeeded()
        viewController.syntaxLanguage = .markdown
        viewController.text = "# Title"

        let storage = try XCTUnwrap(viewController.textStorage)
        let location = (viewController.text as NSString).range(of: "#").location
        let highlightedColor = storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
        XCTAssertTrue(highlightedColor?.isEqual(ThemeManager.shared.syntaxTheme.headingMarker) == true)

        EditorSettings.increaseFontSize()

        let updatedColor = storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
        XCTAssertTrue(updatedColor?.isEqual(ThemeManager.shared.syntaxTheme.headingMarker) == true)
    }

    func testSettingsViewWritesFontSelectionBackToEditorSettings() throws {
        let availableFonts = EditorFontResolver.availableFontIDs()
        let selectedFont = try XCTUnwrap(availableFonts.last)

        let viewController = SettingsViewController()
        viewController.loadViewIfNeeded()

        let popUpButton = try XCTUnwrap(findFontPopUpButton(in: viewController.view))
        XCTAssertEqual(popUpButton.itemTitles, availableFonts.map(\.displayName))

        let targetIndex = try XCTUnwrap(availableFonts.firstIndex(of: selectedFont))
        popUpButton.selectItem(at: targetIndex)
        _ = (popUpButton.target as AnyObject?)?.perform(popUpButton.action, with: popUpButton)

        XCTAssertEqual(EditorSettings.currentFontID(), selectedFont)
    }

    private func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView {
            return textView
        }

        for subview in view.subviews {
            if let textView = findTextView(in: subview) {
                return textView
            }
        }

        return nil
    }

    private func findFontPopUpButton(in view: NSView) -> NSPopUpButton? {
        if let popUpButton = view as? NSPopUpButton,
           popUpButton.itemTitles.contains(EditorFontID.fallback.displayName) {
            return popUpButton
        }

        for subview in view.subviews {
            if let popUpButton = findFontPopUpButton(in: subview) {
                return popUpButton
            }
        }

        return nil
    }

    private nonisolated static func makeUserDefaults() -> UserDefaults {
        let suiteName = "EditorFontTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}
