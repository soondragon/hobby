import SwiftUI

@MainActor
struct ProfileEntryView: View {
    @Environment(ProfileWindowController.self) private var controller: ProfileWindowController?
    @Environment(CompanionStore.self) private var companion: CompanionStore?
    @State private var showingCloud = false
    let language: AppLanguage

    var body: some View {
        if let cloud = companion?.cloudController {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label(cloud.alias ?? "GitHub 클라우드 세이브", systemImage: "icloud")
                        .font(.callout.weight(.semibold))
                    Text(cloud.status).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button("관리") { showingCloud = true }.controlSize(.small)
            }
            .sheet(isPresented: $showingCloud) {
                VStack {
                    CloudAccountView(controller: cloud)
                    Button("닫기") { showingCloud = false }.padding(.bottom)
                }
            }
        } else if let controller {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle")
                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.session.profile?.alias ?? L(language).profileTitle)
                        .font(.callout.weight(.semibold)).lineLimit(1)
                    if controller.session.profile != nil {
                        Text(controller.session.isVerified ? L(language).profileVerified : L(language).profileCached)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                Button(controller.session.profile == nil ? L(language).profileConnect : L(language).profileManage) {
                    controller.open(language: language)
                }
                .controlSize(.small)
            }
        }
    }
}
