import Foundation

extension L {
    // New profile copy follows the app's selected language, with English fallback.
    private func profileText(_ korean: String, _ english: String) -> String { lang == .ko ? korean : english }
    var profileTitle: String { profileText("사용자 프로필", "User profile") }
    var profileConnect: String { profileText("GitHub 로그인", "Sign in with GitHub") }
    var profileManage: String { profileText("프로필", "Profile") }
    var profileDescription: String { profileText("GitHub 아이디를 사용자 별칭으로 표시합니다. 포켓몬과 사용량 데이터는 이 Mac에 유지됩니다.", "Use your GitHub username as your alias. Pokémon and usage data stay on this Mac.") }
    var profilePermissions: String { profileText("공개 프로필만 조회합니다. 저장소·이메일 접근 권한은 요청하지 않습니다.", "Only your public profile is requested. No repository or email permissions.") }
    var profileCached: String { profileText("저장된 프로필 · 연결 확인 필요", "Saved profile · connection not verified") }
    var profileVerified: String { profileText("GitHub 연결 확인됨", "GitHub connection verified") }
    var profileVerify: String { profileText("연결 확인", "Verify connection") }
    var profileDisconnect: String { profileText("이 Mac에서 연결 해제", "Disconnect on this Mac") }
    var profileDisconnectConfirm: String { profileText("연결 해제 확인", "Confirm disconnect") }
    var profileDisconnectHint: String { profileText("이 Mac의 로그인 정보만 제거하며 포켓몬 기록은 유지합니다.", "Removes this Mac's sign-in only. Pokémon records are kept.") }
    var profileDeviceHint: String { profileText("아래 코드를 복사해 GitHub에 입력하세요. 이메일이나 문자로 발송되는 코드가 아닙니다.", "Copy this code and enter it on GitHub. It is not sent by email or text message.") }
    var profileOpenGitHub: String { profileText("GitHub에서 승인", "Authorize on GitHub") }
    var profileCodeCopied: String { profileText("코드 복사됨", "Code copied") }
    var profileCopyCode: String { profileText("코드 복사", "Copy code") }
    var profileWaiting: String { profileText("GitHub 승인을 기다리는 중…", "Waiting for GitHub authorization…") }
    var profileLoading: String { profileText("연결 확인 중…", "Connecting…") }
    var profileSetupRequired: String { profileText("이 빌드는 GitHub 로그인이 아직 설정되지 않았습니다. 로컬 기능은 계속 사용할 수 있습니다.", "GitHub sign-in is not configured in this build. Local features remain available.") }
    var profileCancel: String { profileText("취소", "Cancel") }
    func profileError(_ error: ProfileAccessError) -> String {
        switch error {
        case .notConfigured: return profileSetupRequired
        case .denied: return profileText("GitHub 승인이 취소되었습니다. 다시 로그인할 수 있습니다.", "GitHub authorization was declined. You can sign in again.")
        case .expired: return profileText("인증이 만료되었습니다. 다시 로그인해 주세요.", "Authorization expired. Please sign in again.")
        case .invalidCredential: return profileText("로그인을 확인하지 못했습니다. 다시 로그인해 주세요.", "Unable to verify your identity. Please sign in again.")
        case .rateLimited: return profileText("GitHub 요청이 제한되었습니다. 잠시 후 다시 시도해 주세요.", "GitHub is limiting requests. Please try again later.")
        case .storage: return profileText("프로필 또는 로그인 정보를 저장·제거하지 못했습니다. 다시 시도해 주세요.", "Could not save or remove profile credentials. Please try again.")
        case .invalidResponse: return profileText("GitHub 응답을 확인하지 못했습니다. 다시 시도해 주세요.", "Could not validate the GitHub response. Please try again.")
        case .unavailable: return profileText("연결할 수 없습니다. 네트워크를 확인하고 다시 시도해 주세요.", "Unable to connect. Check your network and try again.")
        }
    }
}
