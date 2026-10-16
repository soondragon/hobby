import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class SkillEffectsTests: XCTestCase {
    func testBundledPixelSheetsDecodeAllFramesWithTransparentCorners() throws {
        for name in ["fire","water","electric","magic","impact","status"] {
            let frames = try XCTUnwrap(SkillSpriteSheet.frames[name])
            XCTAssertEqual(frames.count,6)
            XCTAssertTrue(frames.allSatisfy { $0.width == $0.height })
            XCTAssertNotEqual(frames[0].alphaInfo,.none)
        }
    }
    func testCanonicalMoveIDsResolveDistinctBehaviorAndReferenceTraits() throws {
        XCTAssertEqual(MoveDefinitions.all.count,559)
        let flame = try XCTUnwrap(MoveDefinitions.find(53))
        XCTAssertEqual(flame.type,"fire")
        XCTAssertEqual(flame.power,95)
        XCTAssertEqual(flame.presentation.style,.stream)
        XCTAssertEqual(flame.traits.ailment,"burn")
        XCTAssertEqual(flame.traits.ailment_chance,10)
        XCTAssertEqual(MoveDefinitions.find(83)?.presentation.style,.vortex)
        XCTAssertEqual(MoveDefinitions.find(57)?.presentation.style,.wave)
        XCTAssertEqual(MoveDefinitions.find(87)?.presentation.style,.strike)
        XCTAssertEqual(MoveDefinitions.find(334)?.traits.statChanges.first?.change,2)
        XCTAssertTrue(MoveDefinitions.find(334)?.targetsUser == true)
        XCTAssertNil(MoveDefinitions.find(999999))
    }
    func testFireImpactFramesNeverKeepTheBlueWaterPalette() throws {
        for name in ["fire:fire","fire:impact","fire:magic"] {
            let frames = try XCTUnwrap(SkillSpriteSheet.frames[name])
            for frame in frames {
                let image = NSBitmapImageRep(cgImage: frame)
                var visible = 0
                for y in 0..<image.pixelsHigh {
                    for x in 0..<image.pixelsWide {
                        guard let color = image.colorAt(x: x,y: y)?.usingColorSpace(.deviceRGB),color.alphaComponent > 0.1 else { continue }
                        visible += 1
                        XCTAssertGreaterThanOrEqual(color.redComponent+0.02,color.blueComponent)
                    }
                }
                XCTAssertGreaterThan(visible,0)
            }
        }
    }
    private func room(event: EncounterSkillEvent, serverTime: Double) -> EncounterRoom {
        .init(id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,revision: 5,closed: false,
              members: [.init(isSelf: true,alias: "trainer",pokemon: nil)],inviteCode: nil,serverTime: serverTime,events: [event])
    }
    private func event(id: Int = 1, startsAt: Double = 200.8) -> EncounterSkillEvent {
        .init(id: id,actorIsSelf: true,moveID: 53,moveName: "화염방사",type: "fire",damageClass: "special",target: "selected-pokemon",startsAt: startsAt)
    }
    func testRepeatedRoomReadsNeverRestartOrDuplicateAnEffect() {
        _ = NSApplication.shared
        let stage = DesktopBattleStage(settings: {},hide: {})
        let before = Date()
        stage.synchronize(room(event: event(),serverTime: 200))
        XCTAssertEqual(stage.state.playbacks.count,1)
        let start = stage.state.playbacks[0].start
        XCTAssertEqual(start.timeIntervalSince(before),0.8,accuracy: 0.05)
        stage.synchronize(room(event: event(),serverTime: 200.5))
        XCTAssertEqual(stage.state.playbacks.count,1)
        XCTAssertEqual(stage.state.playbacks[0].start,start)
        stage.synchronize(room(event: event(id: 2,startsAt: 100),serverTime: 200))
        XCTAssertEqual(stage.state.playbacks.count,1)
        stage.synchronize(nil)
        XCTAssertTrue(stage.state.playbacks.isEmpty)
        XCTAssertTrue(stage.state.members.isEmpty)
        stage.stop()
    }
    func testSkillCommandsContainOnlyServerValidatedIdentifiers() throws {
        let data = try JSONEncoder().encode(EncounterSkillCommand(roomID: UUID(),expectedRevision: 4,requestID: UUID(),moveID: 53))
        let command = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String:Any])
        XCTAssertEqual(Set(command.keys),["roomID","expectedRevision","requestID","moveID"])
    }
    func testPlaybackHasBoundedTimelineAndSelfTargetSemantics() {
        let start = Date()
        let playback = SkillPlayback(event: event(),start: start)
        XCTAssertEqual(playback.progress(at: start),0)
        XCTAssertEqual(playback.progress(at: start.addingTimeInterval(2.2)),1,accuracy: 0.0001)
        XCTAssertFalse(playback.event.targetsUser)
        let status = EncounterSkillEvent(id: 2,actorIsSelf: false,moveID: 334,moveName: "철벽",type: "steel",damageClass: "status",target: "user",startsAt: 0)
        XCTAssertTrue(status.targetsUser)
    }
    func testEffectLayerDoesNotDrawAnOpaqueFullscreenBackdrop() throws {
        _ = NSApplication.shared
        let window = EncounterWindowStyle.floatingPanel()
        let host = NSHostingView(rootView: BattleEffects(playbacks: [],ownAnchor: .zero,opponentAnchor: CGPoint(x: 300,y: 200)))
        host.sizingOptions = [];window.contentView = host
        host.frame = NSRect(x: 0,y: 0,width: 450,height: 402);host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds,to: bitmap)
        XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 1,y: 1)).alphaComponent,0,accuracy: 0.01)
        window.close()
    }
}
