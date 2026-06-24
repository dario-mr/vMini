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

    func testFontSizeChangePreservesSyntaxHighlighting() async throws {
        let viewController = EditorViewController()
        viewController.loadViewIfNeeded()
        viewController.syntaxLanguage = .markdown
        viewController.text = "# Title"

        let storage = try XCTUnwrap(viewController.textStorage)
        let location = (viewController.text as NSString).range(of: "#").location
        try await waitForCondition {
            let highlightedColor = storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
            let highlightedFont = storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
            return highlightedColor?.isEqual(ThemeManager.shared.syntaxTheme.headingMarker) == true
                && highlightedFont?.fontDescriptor.symbolicTraits.contains(.bold) == true
        }

        let highlightedColor = storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
        let highlightedFont = storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
        XCTAssertTrue(highlightedColor?.isEqual(ThemeManager.shared.syntaxTheme.headingMarker) == true)
        XCTAssertTrue(highlightedFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)

        EditorSettings.increaseFontSize()

        try await waitForCondition {
            let updatedColor = storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
            let updatedFont = storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
            return updatedColor?.isEqual(ThemeManager.shared.syntaxTheme.headingMarker) == true
                && updatedFont?.fontDescriptor.symbolicTraits.contains(.bold) == true
        }

        let updatedColor = storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
        let updatedFont = storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
        XCTAssertTrue(updatedColor?.isEqual(ThemeManager.shared.syntaxTheme.headingMarker) == true)
        XCTAssertTrue(updatedFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    func testFontChangeKeepsMarkdownHeadingsBoldAndBodyTextRegular() async throws {
        let initialFont = try XCTUnwrap(EditorFontResolver.availableFontIDs().first)
        let alternateFont = EditorFontResolver.availableFontIDs().first(where: { $0 != initialFont }) ?? .fallback
        EditorSettings.setFontID(initialFont)

        let viewController = EditorViewController()
        viewController.loadViewIfNeeded()
        viewController.syntaxLanguage = .markdown
        viewController.text = "# Title\nbody"

        let storage = try XCTUnwrap(viewController.textStorage)
        let nsText = viewController.text as NSString
        let headingLocation = nsText.range(of: "#").location
        let bodyLocation = nsText.range(of: "body").location

        try await waitForCondition {
            let initialHeadingFont = storage.attribute(.font, at: headingLocation, effectiveRange: nil) as? NSFont
            let initialBodyFont = storage.attribute(.font, at: bodyLocation, effectiveRange: nil) as? NSFont
            return initialHeadingFont?.fontDescriptor.symbolicTraits.contains(.bold) == true
                && initialBodyFont?.fontDescriptor.symbolicTraits.contains(.bold) != true
        }

        let initialHeadingFont = storage.attribute(.font, at: headingLocation, effectiveRange: nil) as? NSFont
        let initialBodyFont = storage.attribute(.font, at: bodyLocation, effectiveRange: nil) as? NSFont
        XCTAssertTrue(initialHeadingFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        XCTAssertFalse(initialBodyFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)

        EditorSettings.setFontID(alternateFont)

        try await waitForCondition {
            let updatedHeadingFont = storage.attribute(.font, at: headingLocation, effectiveRange: nil) as? NSFont
            let updatedBodyFont = storage.attribute(.font, at: bodyLocation, effectiveRange: nil) as? NSFont
            return updatedHeadingFont?.fontDescriptor.symbolicTraits.contains(.bold) == true
                && updatedBodyFont?.fontDescriptor.symbolicTraits.contains(.bold) != true
                && updatedBodyFont?.fontName == EditorFontResolver.font(
                    for: alternateFont,
                    size: EditorSettings.currentFontSize()
                ).fontName
        }

        let updatedHeadingFont = storage.attribute(.font, at: headingLocation, effectiveRange: nil) as? NSFont
        let updatedBodyFont = storage.attribute(.font, at: bodyLocation, effectiveRange: nil) as? NSFont
        XCTAssertTrue(updatedHeadingFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        XCTAssertFalse(updatedBodyFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        XCTAssertEqual(updatedBodyFont?.fontName, EditorFontResolver.font(for: alternateFont, size: EditorSettings.currentFontSize()).fontName)
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

    private func waitForCondition(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        pollNanoseconds: UInt64 = 25_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: pollNanoseconds)
        }

        XCTFail("Timed out waiting for condition")
    }
}
