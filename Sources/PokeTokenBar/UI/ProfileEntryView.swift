import SwiftUI

@MainActor
struct ProfileEntryView: View {
    @Environment(ProfileWindowController.self) private var controller: ProfileWindowController?
    let language: AppLanguage

    var body: some View {
        if let controller {
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
