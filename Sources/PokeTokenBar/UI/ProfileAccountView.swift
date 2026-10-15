import AppKit
import SwiftUI

@MainActor
struct ProfileAccountView: View {
    let session: ProfileSession
    let language: AppLanguage
    @State private var copied = false
    @State private var confirmingDisconnect = false
    private var l: L { L(language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(l.profileTitle, systemImage: "person.crop.circle").font(.title2.bold())
            Text(l.profileDescription).font(.callout).foregroundStyle(.secondary)
            if let profile = session.profile {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.alias).font(.title3.bold()).textSelection(.enabled)
                    Text(session.isVerified ? l.profileVerified : l.profileCached)
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button(l.profileVerify) { session.verifySavedProfile() }.disabled(session.isBusy)
                    Button(l.profileConnect) { session.signIn() }.disabled(session.isBusy || !session.configuration.isConfigured)
                }
                if confirmingDisconnect {
                    Text(l.profileDisconnectHint).font(.caption)
                    HStack {
                        Button(l.profileDisconnectConfirm) { session.disconnect(); confirmingDisconnect = false }
                        Button(l.profileCancel) { confirmingDisconnect = false }
                    }
                } else {
                    Button(l.profileDisconnect) { confirmingDisconnect = true }
                }
            } else if !session.isBusy {
                Button(l.profileConnect) { copied = false; session.signIn() }
                    .buttonStyle(.borderedProminent).disabled(!session.configuration.isConfigured)
            }
            if !session.configuration.isConfigured {
                Text(l.profileSetupRequired).font(.callout).foregroundStyle(.secondary)
            }
            if let challenge = session.challenge {
                Divider()
                Text(l.profileDeviceHint).font(.callout)
                Text(challenge.userCode).font(.system(.title, design: .monospaced).bold()).textSelection(.enabled)
                HStack {
                    Button(copied ? l.profileCodeCopied : l.profileCopyCode) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(challenge.userCode, forType: .string)
                        copied = true
                    }
                    Link(l.profileOpenGitHub, destination: challenge.verificationURI)
                }
                Text(l.profileWaiting).font(.caption).foregroundStyle(.secondary)
            } else if session.isBusy {
                Text(l.profileLoading).font(.callout)
            }
            if session.isBusy { Button(l.profileCancel) { session.cancel() } }
            if let error = session.error { Text(l.profileError(error)).font(.callout).foregroundStyle(.red) }
            Divider()
            Text(l.profilePermissions).font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: session.challenge?.userCode) { _, _ in copied = false }
        .padding(22)
        .frame(width: 430, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
