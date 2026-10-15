import SwiftUI

struct BattleEffectPalette {
    static func color(_ type: String) -> Color {
        switch type {
        case "fire": .orange
        case "water", "ice": .cyan
        case "electric": .yellow
        case "grass", "bug": .green
        case "psychic", "fairy": .pink
        case "ghost", "poison": .purple
        case "dragon": .indigo
        case "ground", "rock": .brown
        case "steel": .gray
        case "dark": Color(red: 0.4, green: 0.3, blue: 0.6)
        default: .white
        }
    }
}

/// Pixel sprite animation on a transparent, click-through monitor canvas.
struct BattleEffects: View {
    let playbacks: [SkillPlayback]
    let ownAnchor: CGPoint
    let opponentAnchor: CGPoint
    var frozenProgress: Double? = nil
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: playbacks.isEmpty || frozenProgress != nil)) { clock in
            Canvas { context, _ in
                context.addFilter(.colorMultiply(.white))
                for playback in playbacks {
                    let progress = frozenProgress ?? playback.progress(at: clock.date)
                    guard progress >= 0, progress <= 1 else { continue }
                    let source = playback.event.actorIsSelf ? ownAnchor : opponentAnchor
                    let destination = playback.event.targetsUser ? source : playback.event.actorIsSelf ? opponentAnchor : ownAnchor
                    draw(context: &context, source: source, destination: destination, progress: progress, event: playback.event)
                }
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
    private func draw(context: inout GraphicsContext, source: CGPoint, destination: CGPoint, progress: Double, event: EncounterSkillEvent) {
        // Six authored frames, stepped rather than interpolated; integer-multiple pixel scaling.
        let frame = Int(progress * 24)
        let key = SkillSpriteSheet.key(type: event.type,damageClass: event.damageClass)
        if event.damageClass == "status" {
            SkillSpriteSheet.draw(key,in: &context,at: destination,size: 144,frame: frame,opacity: min(1,(1-progress)*3))
            return
        }
        let dx = destination.x-source.x, dy = destination.y-source.y
        let angle = atan2(dy,dx)
        if event.damageClass != "physical", progress >= 0.12, progress < 0.74 {
            let flight = min(1,(progress-0.12)/0.55)
            for trail in (0..<4).reversed() {
                let t = max(0,flight-Double(trail)*0.075)
                let point = CGPoint(x: source.x+dx*t,y: source.y+dy*t)
                SkillSpriteSheet.draw(key,in: &context,at: point,size: CGFloat(64-trail*8),frame: frame+trail,
                                      angle: angle,opacity: 1-Double(trail)*0.2)
            }
        }
        if progress > 0.62 {
            let impact = (progress-0.62)/0.38
            SkillSpriteSheet.draw("impact",in: &context,at: destination,size: 128,frame: Int(impact*6),opacity: min(1,(1-impact)*3))
            if event.type == "fire" {
                SkillSpriteSheet.draw("fire",in: &context,at: destination,size: 80,frame: frame,angle: -.pi/2,opacity: 1-impact)
            }
        }
    }
}
