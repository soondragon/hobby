import Foundation
import AuthenticationServices

/// AuthenticationServices calls this from an XPC queue, not the MainActor.
/// The lock protects the one-shot continuation, including a failed start racing cancellation.
final class CloudBrowserCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?

    init(_ continuation: CheckedContinuation<URL, Error>) { self.continuation = continuation }

    var handler: @Sendable (URL?, (any Error)?) -> Void {
        { [self] url, error in
            let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
            finish(url: url, failure: cancelled ? .loginCancelled : .browserUnavailable)
        }
    }

    func finish(url: URL?, failure: CloudError = .authentication) {
        let pending = lock.withLock {
            let pending = continuation
            continuation = nil
            return pending
        }
        guard let pending else { return }
        if let url { pending.resume(returning: url) }
        else { pending.resume(throwing: failure) }
    }
}
