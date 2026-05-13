import AppKit

@MainActor
final class OpenFilesSidebarResizer: NSObject {
    static let minimumWidth: CGFloat = 220
    static let maximumWidth: CGFloat = 420
    static let defaultWidth: CGFloat = 300
    static let handleWidth: CGFloat = 12

    private let persistence: WorkspacePersistence
    private weak var view: NSView?
    private var widthConstraint: NSLayoutConstraint?
    private var dragStartWidth: CGFloat = 0

    init(persistence: WorkspacePersistence) {
        self.persistence = persistence
    }

    override convenience init() {
        self.init(persistence: .shared)
    }

    func storedWidth() -> CGFloat {
        let width = persistence.openFilesSidebarWidth
        guard width > 0 else { return Self.defaultWidth }
        return Self.clamp(width)
    }

    func attach(to handle: ResizeHandleView, in view: NSView, widthConstraint: NSLayoutConstraint) {
        self.view = view
        self.widthConstraint = widthConstraint

        let panGesture = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        handle.addGestureRecognizer(panGesture)
        handle.cursor = .resizeLeftRight
    }

    @objc
    private func handlePan(_ gestureRecognizer: NSPanGestureRecognizer) {
        guard
            let widthConstraint,
            let view
        else {
            return
        }

        switch gestureRecognizer.state {
        case .began:
            dragStartWidth = widthConstraint.constant
        case .changed:
            let translation = gestureRecognizer.translation(in: view).x
            widthConstraint.constant = Self.clamp(dragStartWidth + translation)
        case .ended, .cancelled:
            let finalWidth = Self.clamp(widthConstraint.constant)
            widthConstraint.constant = finalWidth
            persistence.openFilesSidebarWidth = finalWidth
        default:
            break
        }
    }

    private static func clamp(_ width: CGFloat) -> CGFloat {
        min(max(width, minimumWidth), maximumWidth)
    }
}
