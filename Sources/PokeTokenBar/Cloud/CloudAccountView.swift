import SwiftUI

@MainActor
struct CloudAccountView: View {
    let controller: CloudCompanionController
    @State private var confirmDiscard = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(controller.alias ?? "GitHub 클라우드 세이브", systemImage: "person.crop.circle.badge.checkmark")
                .font(.headline)
            Text(controller.status).font(.callout).textSelection(.enabled)
            if controller.isBusy { ProgressView().controlSize(.small) }
            if controller.alias == nil {
                Button("GitHub 로그인") { Task { await controller.connect() } }
                Button("저장된 로그인으로 연결") { Task { await controller.connect(restore: true) } }
            } else {
                if !controller.hasRemoteSave && !controller.hasUnsavedChanges {
                    Button("서버에서 새로 시작") { Task { await controller.initialize() } }
                }
                if controller.canRetry {
                    Button("저장 재시도") { Task { await controller.retry() } }
                    Button("로그인을 갱신하고 재시도") { Task { await controller.reconnectAndRetry() } }
                }
                Button("서버에서 다시 불러오기") {
                    if controller.hasUnsavedChanges { confirmDiscard = true }
                    else { Task { await controller.reload() } }
                }
                Button("로그아웃") { controller.disconnect() }.disabled(controller.hasUnsavedChanges)
            }
            Text("GitHub alias는 표시 이름입니다. 세이브 접근은 로그인 계정으로만 허용됩니다.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 340, height: 390, alignment: .topLeading)
        .disabled(controller.isBusy || !controller.isConfigured)
        .confirmationDialog("서버에서 다시 불러오면 아직 저장되지 않은 변경은 버려집니다.", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("변경을 버리고 서버에서 불러오기", role: .destructive) { Task { await controller.discardAndReload() } }
        }
    }
}
