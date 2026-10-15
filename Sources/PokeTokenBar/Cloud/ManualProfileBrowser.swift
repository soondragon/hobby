#if DEBUG
import AppKit

/// Local QA only: let the tester choose a specific browser profile without opening a default browser.
@MainActor
enum ManualProfileBrowser {
    private static var pending: CheckedContinuation<URL, Error>?
    private static var timeout: Task<Void, Never>?

    static func authorize(_ url: URL) async throws -> URL {
        guard pending == nil else { throw CloudError.authentication }
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let destination = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("trainer-manual-authorize-url")
                try url.absoluteString.write(to: destination, atomically: true, encoding: .utf8)
                let callback = destination.deletingLastPathComponent().appendingPathComponent("trainer-manual-callback")
                try? FileManager.default.removeItem(at: callback)
                pending = continuation
                timeout = Task { @MainActor in
                    for _ in 0..<900 {
                        try? await Task.sleep(for: .milliseconds(200))
                        guard !Task.isCancelled else { return }
                        if let value = try? String(contentsOf: callback, encoding: .utf8) {
                            try? FileManager.default.removeItem(at: callback)
                            finish(URL(string: value))
                            return
                        }
                    }
                    guard !Task.isCancelled else { return }
                    finish(nil)
                }
            } catch { continuation.resume(throwing: error) }
        }
    }

    static func finish(_ url: URL?) {
        let continuation = pending
        pending = nil
        for name in ["trainer-manual-authorize-url", "trainer-manual-callback"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name))
        }
        timeout?.cancel()
        timeout = nil
        if let url { continuation?.resume(returning: url) }
        else { continuation?.resume(throwing: CloudError.authentication) }
    }
}
#endif
