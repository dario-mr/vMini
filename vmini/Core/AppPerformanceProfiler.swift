import Foundation
import OSLog

enum AppPerformanceProfiler {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.miniapp.vmini",
        category: "PointsOfInterest"
    )
    private static let signposter = OSSignposter(logger: logger)

    @MainActor
    private static var appActivationState: OSSignpostIntervalState?

    static func makeSignpostID() -> OSSignpostID? {
        signposter.isEnabled ? signposter.makeSignpostID() : nil
    }

    @discardableResult
    static func beginInterval(_ name: StaticString, id: OSSignpostID = .exclusive) -> OSSignpostIntervalState {
        signposter.beginInterval(name, id: id)
    }

    static func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }

    static func measure<T>(_ name: StaticString, _ operation: () throws -> T) rethrows -> T {
        try measure(name, id: OSSignpostID.exclusive, operation)
    }

    nonisolated(nonsending)
    static func measure<T>(_ name: StaticString, _ operation: () async throws -> T) async rethrows -> T {
        try await measure(name, id: OSSignpostID.exclusive, operation)
    }

    static func measure<T>(_ name: StaticString, id: OSSignpostID?, _ operation: () throws -> T) rethrows -> T {
        guard let id else { return try operation() }
        return try measure(name, id: id, operation)
    }

    nonisolated(nonsending)
    static func measure<T>(_ name: StaticString, id: OSSignpostID?, _ operation: () async throws -> T) async rethrows -> T {
        guard let id else { return try await operation() }
        return try await measure(name, id: id, operation)
    }

    private static func measure<T>(_ name: StaticString, id: OSSignpostID, _ operation: () throws -> T) rethrows -> T {
        let state = beginInterval(name, id: id)
        defer { endInterval(name, state) }
        return try operation()
    }

    nonisolated(nonsending)
    private static func measure<T>(_ name: StaticString, id: OSSignpostID, _ operation: () async throws -> T) async rethrows -> T {
        let state = beginInterval(name, id: id)
        defer { endInterval(name, state) }
        return try await operation()
    }

    @MainActor
    static func beginAppActivation() {
        appActivationState = beginInterval("AppActivation")
    }

    @MainActor
    static func endAppActivation() {
        guard let appActivationState else { return }
        endInterval("AppActivation", appActivationState)
        self.appActivationState = nil
    }
}
