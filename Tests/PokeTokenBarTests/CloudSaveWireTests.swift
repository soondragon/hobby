import XCTest
@testable import PokeTokenBar

final class CloudSaveWireTests: XCTestCase {
    private func wire(_ state: CompanionState) throws -> [String: Any] {
        let command = CloudSaveCommand(expectedRevision: 3, requestID: UUID(), operation: "save", state: state)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: CloudSaveWire.encode(command)) as? [String: Any])
        return try XCTUnwrap(body["state"] as? [String: Any])
    }

    func testGeneralFormUsesLegacyWireKeysAndRoundTrips() throws {
        var state = CompanionState()
        state.pendingHatchID = 420
        state.pendingForm = PokemonForm("sunshine")
        state.representativeSpeciesID = 492
        state.representativeForm = PokemonForm("sky")
        let encoded = try wire(state)
        XCTAssertNil(encoded["pendingForm"])
        XCTAssertNil(encoded["representativeForm"])
        XCTAssertEqual(encoded["pendingUnownForm"] as? String, "sunshine")
        XCTAssertEqual(encoded["representativeUnownForm"] as? String, "sky")
        let restored = try JSONDecoder().decode(CompanionState.self, from: JSONSerialization.data(withJSONObject: encoded))
        XCTAssertEqual(restored.pendingForm?.rawValue, "sunshine")
        XCTAssertEqual(restored.representativeForm?.rawValue, "sky")
    }

    func testActiveAndCollectionFormsKeepServerSchemaKeys() throws {
        var state = CompanionState()
        state.active = MonState(baseID: 492, pathIDs: [492], stageIndex: 0, usedAtStage: 0,
                                rarity: .legendary, totalForms: 1, form: PokemonForm("sky"))
        state.dex = [DexEntry(id: "sky-entry", baseID: 492, finalID: 492, chainOrder: [492],
                              rarity: .legendary, caughtAt: nil, form: PokemonForm("sky"))]
        let encoded = try wire(state)
        let active = try XCTUnwrap(encoded["active"] as? [String: Any])
        let dex = try XCTUnwrap(encoded["dex"] as? [[String: Any]])
        XCTAssertNil(active["form"])
        XCTAssertNil(dex[0]["form"])
        XCTAssertEqual(active["unownForm"] as? String, "sky")
        XCTAssertEqual(dex[0]["unownForm"] as? String, "sky")
        let restored = try JSONDecoder().decode(CompanionState.self, from: JSONSerialization.data(withJSONObject: encoded))
        XCTAssertEqual(restored.active?.form?.rawValue, "sky")
        XCTAssertEqual(restored.dex.first?.form?.rawValue, "sky")
    }

    func testDefaultFormDoesNotChangeExistingServerIdentity() throws {
        var state = CompanionState()
        state.pendingHatchID = 351
        state.pendingForm = PokemonForm("normal")
        XCTAssertNil(try wire(state)["pendingUnownForm"])
        state.pendingHatchID = 201
        state.pendingForm = PokemonForm("a")
        XCTAssertEqual(try wire(state)["pendingUnownForm"] as? String, "a")
    }

    func testBackSpritesRemainSeparateFromGeneralFormFrontCache() {
        let form = PokemonForm("sky")
        XCTAssertNotEqual(SpriteStore.cacheKey(speciesID: 492, animated: false, shiny: false, form: form),
                          SpriteStore.cacheKey(speciesID: 492, animated: false, shiny: false, form: form, back: true))
        XCTAssertTrue(SpriteStore.spriteURL(speciesID: 492, animated: false, shiny: false, form: form, back: true).path.hasSuffix("/back/10006.png"))
    }
}
