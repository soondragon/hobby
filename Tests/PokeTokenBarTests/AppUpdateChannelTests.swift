import XCTest
@testable import PokeTokenBar

final class AppUpdateChannelTests: XCTestCase {
    private func isolatedDefaults() -> UserDefaults {
        let suite = "AppUpdateChannelTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }

    @MainActor
    func testCloudRejectsUpstreamEvenWhenNewerAndSkipped() async {
        let checker = UpdateChecker(currentVersion: "0.2.0", defaults: isolatedDefaults(), channel: .cloud) {
            .init(tag: "v99.0.0", url: "https://github.com/chattymin/PokeTokenBar/releases/tag/v99.0.0")
        }
        await checker.check()
        checker.consider(latest: "99.0.0", url: "https://github.com/chattymin/PokeTokenBar/releases/tag/v99.0.0")
        checker.skipCurrent()
        XCTAssertNil(checker.updateTarget)
        XCTAssertFalse(checker.channel.allowsHomebrewUpgrade)
    }

    @MainActor
    func testCloudAcceptsOnlyItsOwnRelease() async {
        let checker = UpdateChecker(currentVersion: "0.2.0", defaults: isolatedDefaults(), channel: .cloud) {
            .init(tag: "v0.3.0", url: "https://hobby-trainer.vercel.app/downloads/cloud/trainer-0.3.0.zip")
        }
        await checker.check()
        XCTAssertEqual(checker.available?.version, "0.3.0")
        checker.skipCurrent()
        XCTAssertEqual(checker.updateTarget?.version, "0.3.0")
        XCTAssertFalse(AppUpdateChannel.cloud.accepts("https://github.com/soondragon/hobby-other/releases/tag/v1.0.0"))
        XCTAssertFalse(AppUpdateChannel.cloud.accepts("https://github.com/soondragon/hobby/releases/tag/v1.0.0?next=evil"))
    }

    func testUnknownBundleFailsClosedToCloudChannel() {
        XCTAssertEqual(AppUpdateChannel.installed(bundle: Bundle(for: Self.self)).repository, "soondragon/hobby")
        XCTAssertTrue(AppUpdateChannel.upstream.allowsHomebrewUpgrade)
    }
}
