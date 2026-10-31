import AppKit

@MainActor
final class EditorFormattingErrorPresenter {
    private let bannerView: ErrorBannerView
    private let scrollView: NSScrollView
    private let textView: NSTextView
    private let windowProvider: () -> NSWindow?

    private var formattingErrorCharacterLocation: Int?
    var onJSONFormattingError: ((String, String) -> Void)?

    init(
        bannerView: ErrorBannerView,
        scrollView: NSScrollView,
        textView: NSTextView,
        windowProvider: @escaping () -> NSWindow?
    ) {
        self.bannerView = bannerView
        self.scrollView = scrollView
        self.textView = textView
        self.windowProvider = windowProvider
    }

    var message: String? {
        bannerView.message
    }

    func presentJSONFormattingError(forSelection: Bool, error: Error, characterOffset: Int) {
        let messageText = "Couldn’t Format JSON"
        let informativeText = forSelection
            ? "The selected text is not valid JSON.\n\n\(error.localizedDescription)"
            : "The current document is not valid JSON.\n\n\(error.localizedDescription)"

        if let onJSONFormattingError {
            onJSONFormattingError(messageText, informativeText)
            return
        }

        let absoluteCharacterLocation: Int
        if let formattingError = error as? JSONPrettifier.FormattingError {
            absoluteCharacterLocation = characterOffset + formattingError.characterIndex
        } else {
            absoluteCharacterLocation = characterOffset
        }

        showFormattingErrorBanner(
            "\(messageText): \(error.localizedDescription)",
            characterLocation: absoluteCharacterLocation
        )
    }

    func dismiss() {
        clear()
    }

    func clear() {
        guard bannerView.message != nil else {
            return
        }

        formattingErrorCharacterLocation = nil
        bannerView.message = nil
    }

    func updateLayout() {
        guard
            let characterLocation = formattingErrorCharacterLocation,
            let clipView = scrollView.contentView as NSClipView?,
            let window = windowProvider()
        else {
            return
        }

        bannerView.updateFrame(
            in: clipView,
            window: window,
            textView: textView,
            characterLocation: characterLocation
        )
    }

    private func showFormattingErrorBanner(_ message: String, characterLocation: Int) {
        formattingErrorCharacterLocation = characterLocation
        bannerView.message = message
        updateLayout()
    }
}
