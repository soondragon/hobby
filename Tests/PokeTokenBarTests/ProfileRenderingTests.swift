import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class ProfileRenderingTests: XCTestCase {
    func testAccountAndAliasRenderWithoutChangingCompanion() async throws {
        let output = ProcessInfo.processInfo.environment["PTB_PROFILE_RENDER_DIR"].map { URL(fileURLWithPath: $0) }
        let cache = ProfileMemory(), vault = CredentialMemory()
        let clock = ProfileTestClock()
        let session = ProfileSession(configuration: GitHubConfiguration(clientID: "test-client"),
            authentication: AuthenticationStub(), profiles: ProfileProviderStub(), credentials: vault,
            repository: cache, now: { clock.date }, sleep: { _ in })
        for language in [AppLanguage.ko, .en] {
            try await capture(ProfileAccountView(session: session, language: language),
                size: NSSize(width: 430, height: 300), output: output?.appendingPathComponent("profile-before-\(language.rawValue).png"))
        }
        session.signIn()
        await awaitProfileOperation { !session.isBusy }
        XCTAssertTrue(session.isVerified)
        for language in [AppLanguage.ko, .en] {
            try await capture(ProfileAccountView(session: session, language: language),
                size: NSSize(width: 430, height: 360), output: output?.appendingPathComponent("profile-after-\(language.rawValue).png"))
        }
        let controller = ProfileWindowController(session: session)
        for language in AppLanguage.allCases {
            try await capture(ProfileEntryView(language: language).environment(controller).padding(14),
                size: NSSize(width: 360, height: 80), output: output?.appendingPathComponent("alias-\(language.rawValue).png"))
        }
        XCTAssertEqual(vault.reads, 0)
    }

    func testPendingChallengeRendersInSeparateAccountWindow() async throws {
        let suspended = AuthenticationStub(Array(repeating: .pending, count: 100))
        let session = ProfileSession(configuration: GitHubConfiguration(clientID: "test-client"),
            authentication: suspended, profiles: ProfileProviderStub(), credentials: CredentialMemory(),
            repository: ProfileMemory(), sleep: { _ in try await Task.sleep(for: .milliseconds(100)) })
        session.signIn()
        await awaitProfileOperation { session.challenge != nil }
        defer { session.cancel() }
        let output = ProcessInfo.processInfo.environment["PTB_PROFILE_RENDER_DIR"].map { URL(fileURLWithPath: $0) }
        try await capture(ProfileAccountView(session: session, language: .ko),
            size: NSSize(width: 430, height: 440), output: output?.appendingPathComponent("profile-pending-ko.png"))
    }

    func testHomeKeepsPokemonContentWithOptionalAlias() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = UserDefaults(suiteName: "profile-render-\(UUID().uuidString)")!
        defaults.set(0, forKey: "refreshInterval")
        let usage = UsageStore(providers: [], discoverClaudeConfigDirs: { [] }, readDefaultIdentity: { nil },
                               autoRefresh: false, defaults: defaults)
        let companion = CompanionStore(provider: ProfileRenderPokemonProvider(), fileURL: root.appendingPathComponent("companion.json"), defaults: defaults)
        let navigation = PopoverNavigation()
        let updater = UpdateChecker(fetchLatest: { nil })
        let cache = ProfileMemory()
        cache.value = sampleGitHubProfile
        let session = ProfileSession(configuration: GitHubConfiguration(clientID: "test-client"),
            authentication: AuthenticationStub(), profiles: ProfileProviderStub(), credentials: CredentialMemory(), repository: cache)
        let controller = ProfileWindowController(session: session)
        let output = ProcessInfo.processInfo.environment["PTB_PROFILE_RENDER_DIR"].map { URL(fileURLWithPath: $0) }
        let home = PopoverView().environment(usage).environment(companion).environment(updater).environment(navigation)
        try await capture(home, size: NSSize(width: 360, height: 680), output: output?.appendingPathComponent("home-before.png"))
        try await capture(home.environment(controller), size: NSSize(width: 360, height: 680), output: output?.appendingPathComponent("home-after.png"))
        XCTAssertNil(companion.state.active)
        XCTAssertTrue(companion.state.dex.isEmpty)
        XCTAssertEqual(companion.state.usedSinceInstall, 0)
        XCTAssertEqual(navigation.tab, .home)
    }

    private func capture<V: View>(_ view: V, size: NSSize, output: URL?) async throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Color.white).environment(\.colorScheme, .light))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFront(nil)
        defer { window.close() }
        await Task.yield()
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.bounds.width, size.width)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 1000)
        if let output { try png.write(to: output) }
    }
}

private struct ProfileRenderPokemonProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}
