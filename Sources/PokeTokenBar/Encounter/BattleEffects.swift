import SwiftUI

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
                    let destination = playback.event.actorIsSelf ? opponentAnchor : ownAnchor
                    SkillEffectRenderer.draw(moveID: playback.event.moveID,
                        parameters: .init(source: source,target: destination,progress: progress),context: &context)
                }
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
