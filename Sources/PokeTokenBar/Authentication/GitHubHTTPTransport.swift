import Foundation

struct GitHubHTTPResponse: Sendable {
    let status: Int
    let data: Data
}

protocol GitHubHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> GitHubHTTPResponse
}

/// Never sends cookies or follows redirects with an Authorization header.
final class GitHubURLTransport: NSObject, GitHubHTTPTransport, URLSessionTaskDelegate, Sendable {
    func send(_ request: URLRequest) async throws -> GitHubHTTPResponse {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, data.count <= 262_144 else {
            throw ProfileAccessError.invalidResponse
        }
        return GitHubHTTPResponse(status: http.statusCode, data: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
