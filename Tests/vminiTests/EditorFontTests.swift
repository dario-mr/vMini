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
        let headingScale = MarkdownAttributeStyler.Constants.headingScales[0]
        let markerColor = ThemeManager.shared.syntaxTheme.headingMarker.withAlphaComponent(
            MarkdownAttributeStyler.Constants.headingMarkerAlpha
        )
        let viewController = EditorViewController()
        viewController.loadViewIfNeeded()
        viewController.syntaxLanguage = .markdown
        viewController.text = "# Title"

        let storage = try XCTUnwrap(viewController.textStorage)
        let location = (viewController.text as NSString).range(of: "#").location
        try await waitForCondition {
            let highlightedColor = storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
            let highlightedFont = storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
            guard let highlightedFont else { return false }
            return highlightedColor?.isEqual(markerColor) == true
                && highlightedFont.fontDescriptor.symbolicTraits.contains(.bold)
                && abs(highlightedFont.pointSize - EditorSettings.currentFontSize() * headingScale) < 0.001
        }

        EditorSettings.increaseFontSize()

        try await waitForCondition {
            let updatedColor = storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
            let updatedFont = storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
            guard let updatedFont else { return false }
            return updatedColor?.isEqual(markerColor) == true
                && updatedFont.fontDescriptor.symbolicTraits.contains(.bold)
                && abs(updatedFont.pointSize - EditorSettings.currentFontSize() * headingScale) < 0.001
        }
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

    func testMarkdownHeadingEditsKeepGutterSize() async throws {
        let viewController = EditorViewController()
        viewController.loadViewIfNeeded()
        viewController.syntaxLanguage = .markdown
        viewController.text = "Heading\n" + Array(repeating: "body", count: 100).joined(separator: "\n")
        let textView = try XCTUnwrap(findTextView(in: viewController.view))
        let storage = try XCTUnwrap(textView.textStorage)
        let ruler = try XCTUnwrap(viewController.view.subviews.compactMap { $0 as? LineNumberRulerView }.first)
        let baseSize = EditorSettings.currentFontSize()
        let initialWidth = ruler.ruleThickness
        let scales: [CGFloat] = [1] + MarkdownAttributeStyler.Constants.headingScales + [1]

        for level in Array(1...7) + Array((0...6).reversed()) {
            let heading = String(repeating: "#", count: level) + (level > 0 ? " " : "") + "Heading"
            let firstLine = (textView.string as NSString).lineRange(for: NSRange(location: 0, length: 0))
            textView.insertText(heading, replacementRange: NSRange(location: 0, length: firstLine.length - 1))
            try await waitForCondition {
                let font = storage.attribute(.font, at: heading.count - 1, effectiveRange: nil) as? NSFont
                guard let font else { return false }
                return abs(font.pointSize - baseSize * scales[level]) < 0.001
                    && font.fontDescriptor.symbolicTraits.contains(.bold) == (1...6).contains(level)
            }
            ruler.invalidateLineNumbers()
            XCTAssertEqual(ruler.ruleThickness, initialWidth, "Heading level \(level) changed the gutter width")
            let bodyFont = storage.attribute(.font, at: heading.count + 1, effectiveRange: nil) as? NSFont
            XCTAssertEqual(bodyFont?.pointSize, baseSize)
        }

        EditorSettings.setFontSize(baseSize + 4)
        try await waitForCondition {
            let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            guard let font else { return false }
            return abs(font.pointSize - EditorSettings.currentFontSize()) < 0.001
        }
        ruler.invalidateLineNumbers()
        XCTAssertGreaterThan(ruler.ruleThickness, initialWidth)
    }

    func testDeletingBlankLineKeepsItsGutterNumberVisibleBeforeSaving() async throws {
        let headingScale = MarkdownAttributeStyler.Constants.headingScales[1]
        EditorSettings.setWordWrapEnabled(true)
        let viewController = EditorViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = NSRect(x: 0, y: 0, width: 700, height: 900)
        viewController.syntaxLanguage = .markdown
        viewController.text = "# Title\n" + String(repeating: "body\n", count: 11)
            + "- " + String(repeating: "Wrapped paragraph. ", count: 25) + "\n\n## Next heading\nBody below"
        viewController.view.layoutSubtreeIfNeeded()
        let textView = try XCTUnwrap(findTextView(in: viewController.view))
        let storage = try XCTUnwrap(textView.textStorage)
        let layout = try XCTUnwrap(textView.layoutManager)
        let container = try XCTUnwrap(textView.textContainer)
        let ruler = try XCTUnwrap(viewController.view.subviews.compactMap { $0 as? LineNumberRulerView }.first)
        let blankLocation = (textView.string as NSString).range(of: "\n\n##").location + 1
        textView.setSelectedRange(NSRange(location: blankLocation, length: 0))
        try await waitForCondition {
            let headingLocation = (storage.string as NSString).range(of: "Next heading").location
            guard let font = storage.attribute(.font, at: headingLocation, effectiveRange: nil) as? NSFont else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.bold)
                && abs(font.pointSize - EditorSettings.currentFontSize() * headingScale) < 0.001
        }
        layout.ensureLayout(for: container)
        let glyph = layout.glyphIndexForCharacter(at: blankLocation)
        let lineRect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let y = Int(lineRect.midY + textView.textContainerOrigin.y - textView.visibleRect.minY)
        let initial = try gutterColor(ruler, atY: y)

        textView.insertNewline(nil)
        try await Task.sleep(nanoseconds: 150_000_000)
        _ = try gutterColor(ruler, atY: y)
        textView.deleteBackward(nil)
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(viewController.currentLineNumber(), 14)
        XCTAssertEqual(try gutterColor(ruler, atY: y), initial)
    }

    private func gutterColor(_ ruler: LineNumberRulerView, atY y: Int) throws -> NSColor {
        let image = NSImage(size: ruler.bounds.size, flipped: true) { _ in
            ruler.draw(ruler.bounds)
            return true
        }
        let data = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        return try XCTUnwrap(bitmap.colorAt(x: 2, y: y))
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
