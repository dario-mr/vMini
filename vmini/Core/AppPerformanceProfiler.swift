import Foundation
import OSLog

enum AppPerformanceProfiler {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.miniapp.vmini",
        category: "Performance"
    )
    private static let signposter = OSSignposter(logger: logger)

    @MainActor
    private static var appActivationState: OSSignpostIntervalState?

    @MainActor
    @discardableResult
    static func beginInterval(_ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name)
    }

    @MainActor
    static func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }

    @MainActor
    static func measure<T>(_ name: StaticString, _ operation: () throws -> T) rethrows -> T {
        let state = beginInterval(name)
        defer { endInterval(name, state) }
        return try operation()
    }

    @MainActor
    static func measure<T>(_ name: StaticString, _ operation: () async throws -> T) async rethrows -> T {
        let state = beginInterval(name)
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
