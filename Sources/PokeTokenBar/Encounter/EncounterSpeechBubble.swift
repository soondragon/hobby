import SwiftUI

struct EncounterSpeechBubble: View {
    let member: EncounterMember?
    let placeholder: String
    var message: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(member.map { "@" + $0.alias } ?? placeholder)
                .font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
            Text(message ?? member?.pokemon?.title ?? "포켓몬 선택 대기")
                .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
        }
        .foregroundStyle(Color(red: 0.16, green: 0.19, blue: 0.25))
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(width: 190, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 17).fill(Color.white.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(Color.black.opacity(0.08)))
        .overlay(alignment: .bottomLeading) {
            BubbleTail().fill(Color.white.opacity(0.97)).frame(width: 15, height: 12).offset(x: 26, y: 10)
        }
        .shadow(color: .black.opacity(0.13), radius: 7, y: 3)
    }
}

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addQuadCurve(to: CGPoint(x: rect.width * 0.15, y: rect.height), control: CGPoint(x: rect.width * 0.55, y: rect.height * 0.5))
            path.addQuadCurve(to: CGPoint(x: rect.width, y: 0), control: CGPoint(x: rect.width * 0.85, y: rect.height))
            path.closeSubpath()
        }
    }
}
