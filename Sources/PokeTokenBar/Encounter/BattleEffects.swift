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

/// Bounded deterministic particles; no screen capture, tint, or desktop modification.
struct BattleEffects: View {
    let playbacks: [SkillPlayback]
    let ownAnchor: CGPoint
    let opponentAnchor: CGPoint
    var frozenProgress: Double? = nil
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: playbacks.isEmpty || frozenProgress != nil)) { clock in
            Canvas { context, _ in
                for playback in playbacks {
                    let progress = frozenProgress ?? playback.progress(at: clock.date)
                    guard progress >= 0, progress <= 1 else { continue }
                    let source = playback.event.actorIsSelf ? ownAnchor : opponentAnchor
                    let destination = playback.event.targetsUser ? source : playback.event.actorIsSelf ? opponentAnchor : ownAnchor
                    draw(context: &context, source: source, destination: destination, progress: progress, event: playback.event)
                }
                let active = playbacks.filter { let p = frozenProgress ?? $0.progress(at: clock.date);return p > 0.36 && p < 0.8 }
                if active.contains(where: { $0.event.type == "fire" && $0.event.damageClass != "status" }),
                   active.contains(where: { $0.event.type == "water" && $0.event.damageClass != "status" }) {
                    let time = frozenProgress ?? clock.date.timeIntervalSinceReferenceDate
                    for index in 0..<20 {
                        let angle = Double(index) * 2.399 + time
                        let reach = Double(index % 5) * 10
                        let point = CGPoint(x: (ownAnchor.x+opponentAnchor.x)/2 + cos(angle)*reach,
                                            y: (ownAnchor.y+opponentAnchor.y)/2 + sin(angle)*reach-Double(index%4)*8)
                        context.fill(Path(ellipseIn: CGRect(x: point.x,y: point.y,width: 16,height: 16)),with: .color(.white.opacity(0.25)))
                    }
                }
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
    private func draw(context: inout GraphicsContext, source: CGPoint, destination: CGPoint, progress: Double, event: EncounterSkillEvent) {
        let color = BattleEffectPalette.color(event.type)
        if event.damageClass == "status" {
            for ring in 0..<4 {
                let radius = 15 + (progress * 90 + Double(ring) * 20).truncatingRemainder(dividingBy: 90)
                let rect = CGRect(x: destination.x - radius, y: destination.y - radius * 0.45, width: radius * 2, height: radius * 0.9)
                context.stroke(Path(ellipseIn: rect), with: .color(color.opacity((1 - progress) * 0.8)), lineWidth: 3)
            }
            return
        }
        let dx = destination.x - source.x, dy = destination.y - source.y
        let distance = max(1, hypot(dx, dy))
        let normal = CGPoint(x: -dy / distance, y: dx / distance)
        let flight = min(1, max(0, (progress - 0.1) / 0.62))
        if event.damageClass == "physical" {
            if progress > 0.48 {
                let impact = min(1, (progress-0.48)/0.52)
                for index in 0..<3 {
                    let shift = Double(index-1)*18
                    var slash = Path()
                    slash.move(to: CGPoint(x: destination.x-35+shift,y: destination.y+40))
                    slash.addQuadCurve(to: CGPoint(x: destination.x+35+shift,y: destination.y-40),control: CGPoint(x: destination.x+40,y: destination.y+15))
                    context.stroke(slash,with: .color(color.opacity(1-impact)),style: StrokeStyle(lineWidth: 7,lineCap: .round))
                }
            }
            return
        }
        if event.type == "electric" {
            var bolt = Path()
            bolt.move(to: source)
            for index in 1...22 {
                let t = Double(index) / 22 * flight
                let zig = index % 2 == 0 ? 15.0 : -15.0
                bolt.addLine(to: CGPoint(x: source.x + dx * t + normal.x * zig, y: source.y + dy * t + normal.y * zig))
            }
            context.stroke(bolt, with: .color(.yellow.opacity(0.25)), lineWidth: 15)
            context.stroke(bolt, with: .color(.white.opacity(0.95)), lineWidth: 3)
        } else {
            let head = CGPoint(x: source.x+dx*flight,y: source.y+dy*flight)
            var stream = Path()
            for index in 0...32 {
                let t = Double(index)/32*flight
                let spread = 5+t*34+sin(t*25+progress*30)*4
                let point = CGPoint(x: source.x+dx*t+normal.x*spread,y: source.y+dy*t+normal.y*spread)
                if index == 0 { stream.move(to: point) } else { stream.addLine(to: point) }
            }
            for index in stride(from: 32,through: 0,by: -1) {
                let t = Double(index)/32*flight
                let spread = 5+t*34+sin(t*25+progress*30)*4
                stream.addLine(to: CGPoint(x: source.x+dx*t-normal.x*spread,y: source.y+dy*t-normal.y*spread))
            }
            stream.closeSubpath()
            context.fill(stream,with: .linearGradient(Gradient(colors: [color.opacity(0.9),color.opacity(0.45),.white.opacity(0.6)]),startPoint: source,endPoint: head))
            var core = Path(); core.move(to: source);core.addLine(to: head)
            context.stroke(core,with: .color((event.type == "fire" ? Color.yellow : .white).opacity(0.8)),lineWidth: 7)
            for index in 0..<110 {
                let seed = Double(index * 37 % 101) / 101
                let along = seed * flight
                guard along >= 0, along <= 1, progress < 0.9 else { continue }
                let spread = sin(Double(index) * 8.3 + progress * 25) * (6 + along * 23)
                let point = CGPoint(x: source.x + dx * along + normal.x * spread, y: source.y + dy * along + normal.y * spread)
                let side = event.type == "fire" ? 6 + seed * 12 : 4 + seed * 8
                let opacity = min(1, (1 - progress) * 2)
                let particleColor = event.type == "fire" && index % 3 == 0 ? Color.yellow : index % 4 == 0 ? .white : color
                context.fill(Path(roundedRect: CGRect(x: point.x, y: point.y, width: side, height: side), cornerRadius: event.type == "water" ? side/2 : 1), with: .color(particleColor.opacity(opacity)))
            }
        }
        if progress > 0.62 {
            let impact = min(1, (progress - 0.62) / 0.38)
            let radius = 15 + impact * 65
            context.stroke(Path(ellipseIn: CGRect(x: destination.x-radius, y: destination.y-radius, width: radius*2, height: radius*2)), with: .color(color.opacity(1-impact)), lineWidth: 5)
            for index in 0..<30 {
                let angle = Double(index) * 2.399
                let reach = impact * (30 + Double(index % 5) * 14)
                let point = CGPoint(x: destination.x + cos(angle)*reach, y: destination.y + sin(angle)*reach)
                context.fill(Path(CGRect(x: point.x,y: point.y,width: 5,height: 5)),with: .color((index%3==0 ? Color.white : color).opacity(1-impact)))
            }
        }
    }
}
