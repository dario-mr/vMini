import AppKit

@MainActor
final class WindowFramePersistence {
    private let persistence: WorkspacePersistence

    init(persistence: WorkspacePersistence) {
        self.persistence = persistence
    }

    convenience init() {
        self.init(persistence: .shared)
    }

    func persist(window: NSWindow?) {
        guard let window else { return }
        persistence.workspaceWindowFrame = NSStringFromRect(window.frame)
    }

    func restoredWindowFrame() -> NSRect? {
        guard
            let storedFrame = persistence.workspaceWindowFrame,
            let frame = windowFrame(from: storedFrame)
        else {
            return nil
        }

        return constrainedWindowFrame(frame)
    }

    func defaultWindowFrame() -> NSRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 700)
        let size = NSSize(
            width: min(1000, visibleFrame.width),
            height: min(700, visibleFrame.height)
        )
        return NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func windowFrame(from storedFrame: String) -> NSRect? {
        let rect = NSRectFromString(storedFrame)
        if rect.width > 0, rect.height > 0 {
            return rect
        }

        let values = storedFrame
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Double($0) }
        guard values.count >= 4, values[2] > 0, values[3] > 0 else {
            return nil
        }

        return NSRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    private func constrainedWindowFrame(_ frame: NSRect) -> NSRect {
        let screen = NSScreen.screens
            .max { lhs, rhs in
                area(of: lhs.visibleFrame.intersection(frame)) < area(of: rhs.visibleFrame.intersection(frame))
            } ?? NSScreen.main

        guard let visibleFrame = screen?.visibleFrame else {
            return frame
        }

        let width = min(frame.width, visibleFrame.width)
        let height = min(frame.height, visibleFrame.height)
        return NSRect(
            x: min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width),
            y: min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - height),
            width: width,
            height: height
        )
    }

    private func area(of rect: NSRect) -> CGFloat {
        max(rect.width, 0) * max(rect.height, 0)
    }
}
