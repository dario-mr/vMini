import Foundation

struct WorkspaceNavigationLocation: Equatable {
    let documentID: ObjectIdentifier
    let selection: NSRange
}

struct WorkspaceNavigationHistory {
    private var back: [WorkspaceNavigationLocation] = []
    private var forward: [WorkspaceNavigationLocation] = []

    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }

    mutating func record(_ location: WorkspaceNavigationLocation) {
        if back.last != location { back.append(location) }
        forward.removeAll()
    }

    mutating func goBack(from current: WorkspaceNavigationLocation) -> WorkspaceNavigationLocation? {
        while let location = back.popLast() {
            guard location != current else { continue }
            forward.append(current)
            return location
        }
        return nil
    }

    mutating func goForward(from current: WorkspaceNavigationLocation) -> WorkspaceNavigationLocation? {
        while let location = forward.popLast() {
            guard location != current else { continue }
            back.append(current)
            return location
        }
        return nil
    }

    mutating func retainDocuments(_ documentIDs: Set<ObjectIdentifier>) {
        back.removeAll { !documentIDs.contains($0.documentID) }
        forward.removeAll { !documentIDs.contains($0.documentID) }
    }
}
