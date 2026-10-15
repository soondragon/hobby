import Foundation

struct CloudConfiguration: Codable, Sendable {
    let supabaseURL: URL
    let publishableKey: String
    let serviceURL: URL

    static func load() throws -> Self? {
        guard let url = Bundle.main.url(forResource: "TrainerCloud", withExtension: "json") else { return nil }
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try value.validate()
        return value
    }

    func validate() throws {
        for url in [supabaseURL, serviceURL] {
            guard url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
                  url.query == nil, url.fragment == nil, url.port == nil || url.port == 443,
                  url.path.isEmpty || url.path == "/" else { throw CloudError.configuration }
        }
        guard supabaseURL.host?.hasSuffix(".supabase.co") == true,
              publishableKey.hasPrefix("sb_publishable_"), publishableKey.count < 4096 else {
            throw CloudError.configuration
        }
    }
}

enum CloudError: Error, LocalizedError, Equatable {
    case configuration, authentication, transport, invalidResponse, conflict, missingSave, locked, storage, growthRejected, rateLimited
    var errorDescription: String? {
        switch self {
        case .configuration: "클라우드 연결 설정이 필요합니다."
        case .authentication: "GitHub 로그인을 다시 확인해 주세요."
        case .transport: "서버에 연결하지 못했습니다. 변경을 멈추고 세이브를 보호합니다."
        case .invalidResponse: "서버 응답을 검증하지 못했습니다."
        case .conflict: "다른 기기에서 세이브가 변경되었습니다. 서버에서 다시 불러와 주세요."
        case .missingSave: "서버 세이브가 없습니다. 서버에서 새로 시작할 수 있습니다."
        case .locked: "서버 세이브를 불러온 뒤 사용할 수 있습니다."
        case .growthRejected: "서버가 성장 변경을 거부했습니다. 변경을 보호한 상태에서 서버 세이브를 확인해 주세요."
        case .rateLimited: "성장 입력이 서버의 허용 속도를 초과했습니다. 잠시 뒤 재시도해 주세요."
        case .storage: "로그인 정보를 안전하게 보관하지 못했습니다."
        }
    }
}
