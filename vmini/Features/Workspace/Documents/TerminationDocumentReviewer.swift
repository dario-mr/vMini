import AppKit

@MainActor
final class TerminationDocumentReviewer: NSObject {
    private var reviewContinuation: CheckedContinuation<Bool, Never>?

    func review(_ documents: [NSDocument]) async -> Bool {
        // NSDocumentController's quit review closes tabs before the user can cancel.
        for document in documents where document.isDocumentEdited {
            let shouldTerminate = await withCheckedContinuation { continuation in
                reviewContinuation = continuation
                document.canClose(
                    withDelegate: self,
                    shouldClose: #selector(document(_:shouldClose:contextInfo:)),
                    contextInfo: nil
                )
            }
            guard shouldTerminate else { return false }
        }
        return true
    }

    @objc
    func document(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        let continuation = reviewContinuation
        reviewContinuation = nil
        continuation?.resume(returning: shouldClose)
    }
}
