import AppKit
import SwiftUI

/// Immutable decoded frames shared by every active playback; no per-frame file I/O.
enum SkillSpriteSheet {
    static let frames: [String: [CGImage]] = {
        var result: [String: [CGImage]] = [:]
        let installed = Bundle.main.resourceURL?.appendingPathComponent("BattleSpells")
        let base: URL?
        if let installed, FileManager.default.fileExists(atPath: installed.path) { base = installed }
        else { base = Bundle.module.url(forResource: "BattleSpells",withExtension: nil) }
        for name in ["fire", "water", "electric", "magic", "impact", "status"] {
            guard let url = base?.appendingPathComponent(name + ".png"),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
            let side = sheet.height
            result[name] = (0..<(sheet.width / side)).compactMap {
                sheet.cropping(to: CGRect(x: $0 * side, y: 0, width: side, height: side))
            }
        }
        return result
    }()
    static func key(type: String, damageClass: String) -> String {
        if damageClass == "status" { return "status" }
        switch type {
        case "fire": return "fire"
        case "water", "ice": return "water"
        case "electric": return "electric"
        default: return "magic"
        }
    }
    static func draw(_ key: String, in context: inout GraphicsContext, at point: CGPoint,
                     size: CGFloat, frame: Int, angle: Double = 0, opacity: Double = 1) {
        guard let sequence = frames[key], !sequence.isEmpty else { return }
        let image = sequence[max(0,frame) % sequence.count]
        var layer = context
        layer.opacity = opacity
        layer.translateBy(x: point.x.rounded(), y: point.y.rounded())
        layer.rotate(by: .radians(angle))
        layer.draw(Image(decorative: image, scale: 1).interpolation(.none),
                   in: CGRect(x: -size/2, y: -size/2, width: size, height: size))
    }
}
