import SwiftUI

@MainActor
struct SettingsView: View {
    let onBack: () -> Void
    let onOpenDevices: () -> Void
    let onOpenDelete: () -> Void

    @StateObject private var vm = DevicesViewModel()
    @State private var doc: DocType?
    @State private var logoutConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar("设置", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 0) {
                        row("登录设备") { onOpenDevices() }
                        divider
                        row("用户协议") { doc = .terms }
                        divider
                        row("隐私政策") { doc = .privacy }
                        divider
                        row("社区公约", showDivider: false) { doc = .rules }
                    }
                    .cardSurface()

                    VStack(spacing: 0) {
                        Button { onOpenDelete() } label: {
                            Text("注销账号")
                                .font(.system(size: 15))
                                .foregroundColor(AppTheme.danger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .frame(height: 56)
                        }
                        .buttonStyle(.plain)
                        divider
                        Button { logoutConfirm = true } label: {
                            Text("退出登录")
                                .font(.system(size: 15))
                                .foregroundColor(AppTheme.danger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .frame(height: 56)
                        }
                        .buttonStyle(.plain)
                    }
                    .cardSurface()

                    Text("服务器：\(ApiConfig.baseURL.absoluteString)")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.tertiaryText)
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.bottom, 24)
            }
        }
        .appBackground()
        .sheet(item: $doc) { doc in
            DocumentSheet(doc: doc)
        }
        .alert("退出登录？", isPresented: $logoutConfirm) {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive) {
                Task { await vm.logout() }
            }
        } message: {
            Text("退出后需要重新输入用户名和密码。")
        }
    }

    private var divider: some View {
        Rectangle().fill(AppTheme.line).frame(height: 1).padding(.leading, 16)
    }

    private func row(_ title: String, showDivider: Bool = true, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack {
                    Text(title)
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.tertiaryText)
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showDivider { divider }
        }
    }
}

private enum DocType: String, Identifiable {
    case terms = "用户协议"
    case privacy = "隐私政策"
    case rules = "社区公约"

    var id: String { rawValue }

    var body: String {
        switch self {
        case .privacy:
            return """
            我们只收集完成校内连接所必需的信息：用户名、学校邮箱验证结果、你主动填写的昵称、简介、头像，以及你发布的需求、评论和私聊内容。

            学校邮箱仅用于确认校内身份，不公开展示。你的联系方式不会出现在需求大厅，只有建立会话后由你自行决定是否提供。

            你可以随时在设置中注销账号。注销后需求立即下架、会话关闭，个人信息将在 15 天内删除。
            """
        case .rules:
            return """
            狮山见只服务华中农业大学在校师生。

            请发布真实、具体、可执行的需求；不要发布广告、引流、诈骗、色情低俗或人身威胁内容。跑腿报酬请私下结算，平台不收款。

            私聊中不要向陌生人转账，不要提供验证码，首次见面选择公共场所。遇到违规内容可以举报，我们会在 24 小时内处理。
            """
        case .terms:
            return """
            欢迎使用狮山见。

            本产品用于校内同学之间发布需求、表达意向并建立联系。注册即表示你同意遵守社区公约，并对发布内容的真实性负责。

            平台会对公开内容做机器审核，高风险内容进入人工复核。违规内容可能被下架、限制功能或封禁账号。
            """
        }
    }
}

@MainActor
private struct DocumentSheet: View {
    let doc: DocType
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(doc.rawValue)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(AppTheme.ink)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(AppTheme.secondaryText)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
            ScrollView {
                Text(doc.body)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.secondaryText)
                    .lineSpacing(5)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 24)
        .presentationDetents([.medium, .large])
    }
}
