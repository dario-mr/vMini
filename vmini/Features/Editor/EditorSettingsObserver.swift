import AppKit

@MainActor
final class EditorSettingsObserver: NSObject {
    private let applyAppearance: () -> Void
    private let applyWordWrap: () -> Void
    private let applyInvisibleCharacters: () -> Void
    private let handleScrollBoundsChange: () -> Void
    private let handleThemeChange: () -> Void
    private var themeObservation: ObservationToken?
    private var settingsObservation: ObservationToken?

    init(
        contentView: NSClipView,
        applyAppearance: @escaping () -> Void,
        applyWordWrap: @escaping () -> Void,
        applyInvisibleCharacters: @escaping () -> Void,
        handleScrollBoundsChange: @escaping () -> Void,
        handleThemeChange: @escaping () -> Void
    ) {
        self.applyAppearance = applyAppearance
        self.applyWordWrap = applyWordWrap
        self.applyInvisibleCharacters = applyInvisibleCharacters
        self.handleScrollBoundsChange = handleScrollBoundsChange
        self.handleThemeChange = handleThemeChange
        super.init()

        contentView.postsBoundsChangedNotifications = true

        settingsObservation = EditorSettings.observe { [weak self] _ in
            guard let self else { return }
            self.applyAppearance()
            self.applyWordWrap()
            self.applyInvisibleCharacters()
        }
        themeObservation = ThemeManager.shared.observe { [weak self] _ in
            self?.handleThemeChange()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: contentView
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    private func handleBoundsDidChange() {
        handleScrollBoundsChange()
    }
}
