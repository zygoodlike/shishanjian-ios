import SwiftUI
import PhotosUI
import UIKit

@MainActor
struct MeView: View {
    let onOpenCards: () -> Void
    let onOpenInterests: () -> Void
    let onOpenReceivedInterests: () -> Void
    let onOpenReceivedComments: () -> Void
    let onOpenFeedback: () -> Void
    let onOpenMyFeedback: () -> Void
    let onOpenSettings: () -> Void
    let onOpenDevices: () -> Void

    @StateObject private var vm = MeViewModel()
    @ObservedObject private var auth = AppServices.shared.auth
    @State private var editOpen = false
    @State private var logoutConfirm = false

    /// 自己的资料：接口返回前直接用登录态缓存，不出现「加载中」。
    private var userId: Int64 { vm.profile?.user?.id ?? auth.userId ?? 0 }
    private var nickname: String { vm.profile?.user?.nickname ?? auth.session?.nickname ?? "" }
    private var username: String? { vm.profile?.user?.username ?? auth.session?.username }
    private var avatar: String? { vm.profile?.user?.avatarKey ?? auth.session?.avatarKey }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("我的")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundColor(AppTheme.ink)
                Spacer()
                RefreshButton {
                    Task { await vm.load(bypassCache: true) }
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.vertical, 16)

            if let error = vm.error, vm.profile == nil, auth.session == nil {
                Spacer()
                ErrorStateView(message: error) { Task { await vm.load() } }
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        profileRow
                        menuGroup("我的内容") {
                            menuRow("我的需求", symbol: "doc.text", action: onOpenCards)
                            menuRow("我的意向", symbol: "heart", action: onOpenInterests)
                            menuRow("收到的意向", symbol: "envelope", action: onOpenReceivedInterests)
                            menuRow("收到的评论", symbol: "bubble.left", action: onOpenReceivedComments, showDivider: false)
                        }
                        menuGroup("账号与服务") {
                            menuRow("意见反馈", symbol: "square.and.pencil", action: onOpenFeedback)
                            menuRow("我的反馈", symbol: "list.bullet.rectangle", action: onOpenMyFeedback)
                            menuRow("安全中心", symbol: "lock", action: onOpenDevices)
                            menuRow("设置", symbol: "gearshape", action: onOpenSettings, showDivider: false)
                        }
                        Button {
                            logoutConfirm = true
                        } label: {
                            Text("退出登录")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AppTheme.danger)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .cardSurface()
                        }
                        .buttonStyle(.plain)
                        Text("狮山见 · 校内连接，从一条需求开始")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.tertiaryText)
                    }
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.bottom, 24)
                }
            }
        }
        .appBackground()
        .task { await vm.loadIfStale() }
        .sheet(isPresented: $editOpen) {
            if let profile = vm.profile {
                EditProfileSheet(profile: profile, vm: vm, onOpenFeedback: onOpenFeedback)
            }
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

    private var profileRow: some View {
        Button {
            if vm.profile != nil { editOpen = true }
        } label: {
            HStack(spacing: 14) {
                AvatarBlock(
                    userId: userId,
                    name: nickname,
                    imageURL: avatar,
                    size: 64
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(nickname)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(AppTheme.ink)
                    if let username, !username.isEmpty {
                        Text("@\(username)")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.tertiaryText)
                    }
                    HStack(spacing: 5) {
                        Circle()
                            .fill(AppTheme.trustGreen)
                            .frame(width: 7, height: 7)
                        Text("已认证学校邮箱")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.trustGreen)
                    }
                    if let bio = vm.profile?.user?.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text("编辑")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.tertiaryText)
            }
            .padding(16)
            .cardSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 菜单分组：12 号弱文字组标题 + 白底圆角卡片。
    private func menuGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.tertiaryText)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                content()
            }
            .cardSurface()
        }
    }

    private func menuRow(
        _ title: String,
        symbol: String,
        action: @escaping () -> Void,
        showDivider: Bool = true
    ) -> some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: 17))
                        .foregroundColor(AppTheme.secondaryText)
                        .frame(width: 20)
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
            if showDivider {
                // 组内分割线从文字处开始
                Rectangle().fill(AppTheme.line).frame(height: 1).padding(.leading, 48)
            }
        }
    }
}

@MainActor
private struct EditProfileSheet: View {
    let profile: Profile
    @ObservedObject var vm: MeViewModel
    let onOpenFeedback: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var nickname: String
    @State private var bio: String
    @State private var avatarData: Data?
    @State private var pickerItem: PhotosPickerItem?

    init(profile: Profile, vm: MeViewModel, onOpenFeedback: @escaping () -> Void) {
        self.profile = profile
        self.onOpenFeedback = onOpenFeedback
        _vm = ObservedObject(wrappedValue: vm)
        _nickname = State(initialValue: profile.user?.nickname ?? "")
        _bio = State(initialValue: profile.user?.bio ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("编辑资料")
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
            .padding(.bottom, 16)

            PhotosPicker(selection: $pickerItem, matching: .images) {
                ZStack {
                    if let avatarData, let image = UIImage(data: avatarData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    } else {
                        AvatarBlock(
                            userId: profile.user?.id ?? 0,
                            name: nickname,
                            imageURL: profile.user?.avatarKey,
                            size: 72
                        )
                    }
                }
            }
            .buttonStyle(.plain)
            Text("点击更换头像")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.tertiaryText)
                .padding(.top, 6)

            FieldLabel(text: "昵称")
                .padding(.top, 18)
            AuthField(text: $nickname, placeholder: "2–12 个字")
                .padding(.top, 8)
            FieldLabel(text: "简介")
                .padding(.top, 16)
            TextEditor(text: $bio)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 88)
                .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.soft))
                .padding(.top, 8)
                .onChange(of: bio) { _, value in
                    if value.count > 100 { bio = String(value.prefix(100)) }
                }
            if let error = vm.error {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.danger)
                    .padding(.top, 10)
                if vm.avatarRejected {
                    Button("去反馈") {
                        dismiss()
                        onOpenFeedback()
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.accentDeep)
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
            }
            PrimaryButton(
                title: "保存",
                loading: vm.saving,
                enabled: (2...12).contains(nickname.count)
            ) {
                Task {
                    if await vm.saveProfile(nickname: nickname, bio: bio) {
                        dismiss()
                    }
                }
            }
            .padding(.top, 20)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 28)
        .presentationDetents([.large])
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    avatarData = data
                    _ = await vm.uploadAvatar(data)
                }
            }
        }
    }
}
