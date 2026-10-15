import Foundation

struct CloudEmptyResponse: Decodable, Sendable {}

/// An ephemeral transport never follows redirects carrying a bearer token.
final class CloudTransport: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func request<T: Decodable & Sendable>(_ type: T.Type, url: URL, method: String = "GET",
                                          token: String? = nil, key: String? = nil, body: Data? = nil) async throws -> T {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let key { request.setValue(key, forHTTPHeaderField: "apikey") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let data: Data; let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw CloudError.transport }
        guard let http = response as? HTTPURLResponse else { throw CloudError.invalidResponse }
        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw CloudError.authentication
        case 409: throw CloudError.conflict
        case 422: throw CloudError.growthRejected
        case 429: throw CloudError.rateLimited
        default: throw CloudError.transport
        }
        if data.isEmpty, let empty = CloudEmptyResponse() as? T { return empty }
        guard data.count <= 2_097_152 else { throw CloudError.invalidResponse }
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw CloudError.invalidResponse }
    }
}
