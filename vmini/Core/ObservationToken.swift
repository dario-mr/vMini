import Foundation

final class ObservationToken {
    private var cancelHandler: (() -> Void)?

    init(_ cancelHandler: @escaping () -> Void) {
        self.cancelHandler = cancelHandler
    }

    func cancel() {
        cancelHandler?()
        cancelHandler = nil
    }

    deinit {
        cancel()
    }
}
