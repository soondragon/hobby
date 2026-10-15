import XCTest
import AppKit
import SwiftUI
@testable import PokeTokenBar

private actor EncounterTestRepository: EncounterServing {
    let id = UUID()
    var count = 0
    var pending: CheckedContinuation<EncounterRoom, Error>?
    var hold = false
    func setHold() { hold = true }
    func commandCount() -> Int { count }
    func release() { pending?.resume(returning: room(code: "a".padding(toLength: 32, withPad: "a", startingAt: 0))); pending = nil }
    private func room(code: String? = nil) -> EncounterRoom {
        .init(id: id, revision: 1, closed: false, members: [.init(isSelf: true, alias: "trainer", pokemon: nil)], inviteCode: code)
    }
    func roster(token: String) async throws -> EncounterRoster { .init(choices: [], room: nil) }
    func command(_ command: EncounterCommand, token: String) async throws -> EncounterRoom {
        count += 1
        if hold { return try await withCheckedThrowingContinuation { pending = $0 } }
        return room(code: command.action == "create" ? String(repeating: "a", count: 32) : nil)
    }
}

@MainActor
final class EncounterTests: XCTestCase {
    func testEmptyAccountAndInvitationSurviveRefreshWithoutInventingPokemon() async {
        let repository = EncounterTestRepository()
        let controller = EncounterController(repository: repository, token: { "session" })
        await controller.refresh()
        XCTAssertTrue(controller.connected)
        XCTAssertTrue(controller.choices.isEmpty)
        XCTAssertNil(controller.room)
        await controller.perform("create")
        let code = controller.room?.inviteCode
        await controller.refresh()
        XCTAssertEqual(controller.room?.inviteCode, code)
        XCTAssertEqual(controller.room?.members.count, 1)
        XCTAssertNil(controller.room?.members.first?.pokemon)
    }

    func testMutationsSerializeAndLateResponseCannotRestoreLoggedOutRoom() async {
        let repository = EncounterTestRepository()
        await repository.setHold()
        let controller = EncounterController(repository: repository, token: { "session" })
        let first = Task { await controller.perform("create") }
        for _ in 0..<1000 {
            if await repository.commandCount() == 1 { break }
            await Task.yield()
        }
        XCTAssertTrue(controller.busy)
        await controller.perform("create")
        let commands = await repository.commandCount()
        XCTAssertEqual(commands, 1)
        controller.stop(clear: true)
        await repository.release()
        await first.value
        XCTAssertNil(controller.room)
        XCTAssertTrue(controller.choices.isEmpty)
        XCTAssertFalse(controller.busy)
    }

    func testFrontAndBackSpritePathsAndCachesRemainSeparate() {
        XCTAssertEqual(SpriteStore.spriteURL(speciesID: 6, animated: false, shiny: false).absoluteString,
                       "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/6.png")
        XCTAssertEqual(SpriteStore.spriteURL(speciesID: 6, animated: false, shiny: true, back: true).path,
                       "/PokeAPI/sprites/master/sprites/pokemon/back/shiny/6.png")
        XCTAssertNotEqual(SpriteStore.cacheKey(speciesID: 6, animated: false, shiny: false),
                          SpriteStore.cacheKey(speciesID: 6, animated: false, shiny: false, back: true))
    }

    func testDesktopCanvasHasTransparentPixelsAndNoWindowChrome() throws {
        _ = NSApplication.shared
        let window = EncounterWindowStyle.floatingPanel()
        let host = NSHostingView(rootView: EncounterDesktopView(members: [], settings: {}, hide: {}))
        host.sizingOptions = []
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 450, height: 402)
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor.alphaComponent, 0)
        XCTAssertFalse(window.styleMask.contains(.titled))
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 1, y: 1)).alphaComponent, 0, accuracy: 0.01)
        window.close()
    }

    func testCommandsNeverContainAnotherOwnerOrPokemonStats() throws {
        let command = EncounterCommand(action: "select", roomID: UUID(), expectedRevision: 3, individualID: "owned")
        let data = try JSONEncoder().encode(command)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["action", "roomID", "expectedRevision", "individualID"])
    }
}
