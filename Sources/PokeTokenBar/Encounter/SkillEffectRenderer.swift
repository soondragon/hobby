import SwiftUI

/// Each instance supplies geometry only; move identity, palette and behavior come from the registry.
struct SkillEffectParameters {
    let source: CGPoint
    let target: CGPoint
    let progress: Double
    var scale: Double = 1
    var intensity: Double = 1
}

enum SkillEffectRenderer {
    static func draw(moveID: Int, parameters p: SkillEffectParameters, context: inout GraphicsContext) {
        guard let move = MoveDefinitions.find(moveID), (0...1).contains(p.progress) else { return }
        let progress = p.progress
        let frame = Int(progress*24)
        let size = min(1.5,max(0.5,p.scale))
        let opacity = min(1,max(0,p.intensity))
        let source = p.source, target = move.targetsUser ? p.source : p.target
        let dx = target.x-source.x, dy = target.y-source.y
        let angle = atan2(dy,dx)
        let style = move.presentation.style
        let type = move.presentation.color
        let sheet = SkillSpriteSheet.key(type: type,damageClass: "special")
        func stamp(_ key: String,_ point: CGPoint,_ side: Double,_ turn: Double = 0,_ alpha: Double = 1) {
            SkillSpriteSheet.draw(key,in: &context,at: point,size: side*size,frame: frame,angle: turn,opacity: alpha*opacity,type: type)
        }
        switch style {
        case .shield, .boost, .pulse, .heal:
            stamp(style == .shield ? "status" : "magic",target,style == .shield ? 128 : 96,0,min(1,(1-progress)*3))
        case .weather:
            for index in 0..<12 {
                let x = (source.x+target.x)/2+Double(index%6-3)*28
                let y = min(source.y,target.y)-30+Double(index/6)*45+progress*65
                stamp(sheet,CGPoint(x: x,y: y),24,.pi/2,1-progress)
            }
        case .vortex:
            for index in 0..<7 {
                let rotation = progress * .pi * 4 + Double(index)*0.9
                stamp(sheet,CGPoint(x: target.x+cos(rotation)*42,y: target.y+sin(rotation)*25),40,rotation,1-progress*0.7)
            }
        case .contact, .burst, .strike:
            if progress > 0.35 {
                stamp(style == .strike ? "electric" : style == .burst ? sheet : "impact",target,112,-.pi/2,1-progress)
            }
        case .projectile, .stream, .wave, .bolt, .drain:
            if progress >= 0.12, progress < 0.74 {
                let flight = min(1,(progress-0.12)/0.55)
                let count = style == .stream ? 9 : style == .wave ? 6 : 3
                for index in (0..<count).reversed() {
                    let fraction = max(0,flight-Double(index)*0.065)
                    let t = style == .drain ? 1-fraction : fraction
                    let point = CGPoint(x: source.x+dx*t,y: source.y+dy*t)
                    stamp(sheet,point,style == .wave ? 80 : max(24,64-Double(index)*4),style == .drain ? angle + .pi : angle,1-Double(index)/Double(count)*0.6)
                }
            }
        }
        if move.damageClass != "status", progress > 0.68 {
            stamp(type == "fire" ? "fire" : "impact",target,96,-.pi/2,min(1,(1-progress)*4))
        }
    }
}
