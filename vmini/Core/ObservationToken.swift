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

/// The observers of one piece of state: each is called once when added and again on every change.
@MainActor
final class Observers<State> {
    private var observers: [UUID: (State) -> Void] = [:]

    func add(_ observer: @escaping (State) -> Void, initialState: State) -> ObservationToken {
        let identifier = UUID()
        observers[identifier] = observer
        observer(initialState)
        return ObservationToken { [weak self] in
            self?.observers.removeValue(forKey: identifier)
        }
    }

    func notify(_ state: State) {
        for observer in observers.values {
            observer(state)
        }
    }
}
