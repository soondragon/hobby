import Foundation

struct CloudEmptyResponse: Decodable, Sendable {}
private struct CloudFailureDetail: Decodable { let detail: String }

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
        case 403:
            if data.count <= 4096,
               (try? JSONDecoder().decode(CloudFailureDetail.self, from: data))?.detail == "github_public_profile_only" {
                throw CloudError.publicProfileOnly
            }
            throw CloudError.authentication
        case 401:
            #if DEBUG
            if ProcessInfo.processInfo.environment["TRAINER_PROFILE_MANUAL_BROWSER"] == "1", url.path == "/api/auth/github/exchange",
               let detail = try? JSONDecoder().decode(CloudFailureDetail.self,from: data).detail,
               ["github_authentication_failed","github_pkce_verification_failed","authentication_required"].contains(detail) {
                throw NSError(domain: "TrainerAuthentication",code: 401,userInfo: [NSLocalizedDescriptionKey:"인증 진단: " + detail])
            }
            #endif
            if url.path == "/api/auth/github/exchange" { throw CloudError.githubExchangeRejected }
            if url.path == "/api/auth/refresh" { throw CloudError.sessionExpired }
            throw CloudError.authentication
        case 503:
            if data.count <= 4096,
               (try? JSONDecoder().decode(CloudFailureDetail.self,from: data))?.detail == "github_authentication_configuration" {
                throw CloudError.serverAuthenticationConfiguration
            }
            throw CloudError.transport
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
