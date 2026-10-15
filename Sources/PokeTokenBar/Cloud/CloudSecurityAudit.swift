#if DEBUG
import Foundation
import Observation
import SwiftUI

/// Explicit diagnostic mode: credentials and player snapshots remain in memory only.
@MainActor @Observable
final class CloudSecurityAudit {
    var status = "두 계정을 순서대로 연결하세요. 로그인 정보와 세이브는 파일로 저장하지 않습니다."
    var aliases = [String?](repeating: nil, count: 2)
    var busy = false
    var results: [String] = []
    private let configuration: CloudConfiguration
    private let accounts: [CloudAuthentication]
    private var owners: [UUID?] = [nil, nil]
    private let session: URLSession

    init(configuration: CloudConfiguration) {
        self.configuration = configuration
        accounts = (0..<2).map { _ in CloudAuthentication(configuration: configuration, persistCredentials: false) }
        let options = URLSessionConfiguration.ephemeral
        options.httpCookieStorage = nil
        options.urlCache = nil
        options.timeoutIntervalForRequest = 20
        session = URLSession(configuration: options)
    }

    func connect(_ index: Int) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await accounts[index].signIn()
            let save = try await CloudSaveRepository(configuration: configuration).read(token: accounts[index].accessToken())
            let expected = index == 0 ? "soondragon" : "yongari9292"
            guard save.alias.lowercased() == expected, save.ownerID == accounts[index].userID else {
                try await accounts[index].signOut()
                status = "계정이 다릅니다. GitHub를 @\(expected)로 전환한 후 다시 연결하세요."
                return
            }
            aliases[index] = save.alias
            owners[index] = save.ownerID
            status = "@\(save.alias) 연결 확인 · 서버 버전 \(save.revision)"
        } catch { status = error.localizedDescription }
    }

    private func request(_ path: String, account: Int, method: String = "GET", body: Data? = nil,
                         database: Bool = false, profile: String? = nil) async throws -> (Int, Data) {
        let base = database ? configuration.supabaseURL : configuration.serviceURL
        guard let url = URL(string: path, relativeTo: base)?.absoluteURL else { throw CloudError.configuration }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(try await accounts[account].accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if database { request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey") }
        if let profile { request.setValue(profile, forHTTPHeaderField: method == "GET" ? "Accept-Profile" : "Content-Profile") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CloudError.invalidResponse }
        return (response.statusCode, data)
    }

    private func check(_ label: String, _ status: Int, allowed: Set<Int>) throws {
        guard allowed.contains(status) else {
            results.append("FAIL \(label): HTTP \(status)")
            throw CloudError.invalidResponse
        }
        results.append("PASS \(label): HTTP \(status)")
    }

    func run() async {
        guard !busy, aliases.allSatisfy({ $0 != nil }), owners[0] != owners[1] else { return }
        busy = true
        results = []
        defer { busy = false }
        do {
            for index in 0..<2 {
                let own = try await CloudSaveRepository(configuration: configuration).read(token: accounts[index].accessToken())
                guard own.ownerID == owners[index], own.alias == aliases[index] else { throw CloudError.invalidResponse }
                results.append("PASS @\(own.alias): 본인 UUID·alias 일치")
                let foreign = owners[1-index]!.uuidString
                let prefix = "@\(own.alias)"
                for table in ["trainer_profiles", "trainer_saves", "trainer_collection", "trainer_inventory", "trainer_candy_ledger", "trainer_save_operations"] {
                    let (code, _) = try await request("/rest/v1/\(table)?owner_id=eq.\(foreign)&select=owner_id", account: index, database: true)
                    try check("\(prefix) 타 계정 \(table) 조회", code, allowed: [401,403])
                }
                let (patch, _) = try await request("/rest/v1/trainer_saves?owner_id=eq.\(foreign)", account: index,
                    method: "PATCH", body: JSONSerialization.data(withJSONObject: ["revision": own.revision]), database: true)
                try check("\(prefix) 타 계정 수정", patch, allowed: [401,403])
                let (selector, _) = try await request("/api/companion?alias=\(aliases[1-index]!)", account: index)
                try check("\(prefix) alias 선택 우회", selector, allowed: [400,422])
                let (privateCode, _) = try await request("/rest/v1/growth_policy?select=owner_id", account: index, database: true, profile: "trainer_internal")
                try check("\(prefix) 내부 정책 스키마", privateCode, allowed: [400,403,404,406])
                let (raw, _) = try await request("/rest/v1/rpc/write_snapshot", account: index, method: "POST", body: Data("{}".utf8), database: true)
                try check("\(prefix) 원시 저장 우회", raw, allowed: [403,404])
                // A valid owner revision exercises the growth validator, not the CAS conflict path.
                let (_, rawEnvelope) = try await request("/api/companion", account: index)
                guard let envelope = try JSONSerialization.jsonObject(with: rawEnvelope) as? [String: Any],
                      var state = envelope["state"] as? [String: Any] else { continue }
                state["usedSinceInstall"] = (state["usedSinceInstall"] as? Int ?? 0) + 1_000_000
                let forged: [String: Any] = ["schemaVersion": 1, "expectedRevision": own.revision,
                    "requestID": UUID().uuidString, "operation": "save", "state": state]
                let (growth, _) = try await request("/api/companion", account: index, method: "PUT", body: JSONSerialization.data(withJSONObject: forged))
                try check("\(prefix) 근거 없는 성장", growth, allowed: [422])
                let after = try await CloudSaveRepository(configuration: configuration).read(token: accounts[index].accessToken())
                guard after.revision == own.revision else { throw CloudError.invalidResponse }
                results.append("PASS \(prefix) 거절 후 서버 버전 불변")
            }
            status = "두 실제 GitHub 계정의 격리 검증 통과 (\(results.count)개)."
        } catch { status = "검증 중단: \(error.localizedDescription)" }
    }
}

struct CloudSecurityAuditView: View {
    @State var audit: CloudSecurityAudit
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("GitHub 다계정 보안 검증").font(.headline)
            Text(audit.status).font(.caption)
            HStack {
                Button(audit.aliases[0].map { "@" + $0 } ?? "1. soondragon 로그인") { Task { await audit.connect(0) } }
                Button(audit.aliases[1].map { "@" + $0 } ?? "2. yongari9292 로그인") { Task { await audit.connect(1) } }
            }.disabled(audit.busy)
            Button("두 계정 접근 차단 검증") { Task { await audit.run() } }
                .disabled(audit.busy || audit.aliases.contains(where: { $0 == nil }))
            ScrollView { VStack(alignment: .leading) { ForEach(Array(audit.results.enumerated()), id: \.offset) { _, line in Text(line).font(.system(size: 10, design: .monospaced)) } } }
        }.padding(20).frame(width: 660, height: 560)
    }
}
#endif
