import SwiftUI

@MainActor
final class UserProfileViewModel: ObservableObject {
    @Published var profile: UserProfile?
    @Published var loading = true
    @Published var error: String?

    private let api = AppServices.shared.api
    private let userId: Int64

    init(userId: Int64) {
        self.userId = userId
    }

    func load() async {
        loading = profile == nil
        error = nil
        do {
            profile = try await api.userProfile(id: userId)
            loading = false
        } catch {
            loading = false
            self.error = error.localizedDescription
        }
    }
}

@MainActor
struct UserProfileView: View {
    let userId: Int64
    let onBack: () -> Void
    let onOpenCard: (Int64) -> Void
    let onOpenChat: (Int64) -> Void

    @StateObject private var vm: UserProfileViewModel

    init(
        userId: Int64,
        onBack: @escaping () -> Void,
        onOpenCard: @escaping (Int64) -> Void,
        onOpenChat: @escaping (Int64) -> Void
    ) {
        self.userId = userId
        self.onBack = onBack
        self.onOpenCard = onOpenCard
        self.onOpenChat = onOpenChat
        _vm = StateObject(wrappedValue: UserProfileViewModel(userId: userId))
    }

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar("", onBack: onBack)
            if vm.loading && vm.profile == nil {
                SkeletonDetail()
                Spacer()
            } else if let error = vm.error, vm.profile == nil {
                Spacer()
                ErrorStateView(message: error) { Task { await vm.load() } }
                Spacer()
            } else if let profile = vm.profile, let user = profile.user {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        LinearGradient(
                            colors: [Color(hex: 0xDCE9FF), Color(hex: 0xEAF1FF), Color(hex: 0xF4F7FF)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                        // AvatarBlock 自己订阅该用户的资料缓存
                        AvatarBlock(
                            userId: user.id,
                            name: user.nickname,
                            imageURL: user.avatarKey,
                            size: 84
                        )
                        .padding(.top, 12)

                        HStack(spacing: 8) {
                            ProfileNameText(userId: user.id, fallback: user.nickname ?? "")
                                .font(.system(size: 22, weight: .heavy))
                                .foregroundColor(AppTheme.ink)
                            HStack(spacing: 4) {
                                Circle().fill(AppTheme.trustGreen).frame(width: 7, height: 7)
                                Text("已认证")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.trustGreen)
                            }
                        }
                        .padding(.top, 10)

                        if let bio = user.bio, !bio.isEmpty {
                            Text(bio)
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.secondaryText)
                                .lineSpacing(4)
                                .padding(.top, 6)
                        }

                        HStack {
                            if profile.mine {
                                SecondaryButton(title: "这是你", enabled: false, fillWidth: true) {}
                            } else if profile.canChat, let convId = profile.conversationId {
                                PrimaryButton(title: "私聊") { onOpenChat(convId) }
                            } else {
                                SecondaryButton(
                                    title: "对方同意后可私聊",
                                    enabled: false,
                                    fillWidth: true
                                ) {}
                            }
                        }
                        .padding(.top, 16)

                        Text("公开作品 \(profile.works?.count ?? 0)")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(AppTheme.ink)
                            .padding(.top, 24)
                            .padding(.bottom, 12)

                        if let works = profile.works, !works.isEmpty {
                            ForEach(works) { card in
                                workCard(card)
                                    .onTapGesture { onOpenCard(card.id) }
                                Spacer().frame(height: 10)
                            }
                        } else {
                            EmptyStateView(title: "还没有公开的作品", subtitle: "TA 发布的需求会出现在这里")
                        }
                        Spacer().frame(height: 30)
                    }
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.bottom, 24)
                }
            }
        }
        .appBackground()
        .task { await vm.load() }
    }

    private func workCard(_ card: Card) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.soft)
                if let cover = card.images?.first {
                    CachedImage(url: ApiConfig.absolute(cover), maxPoint: 72) {
                        AppTheme.soft
                    }
                } else {
                    SceneChip(scene: card.scene)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(card.title ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.ink)
                    .lineLimit(2)
                Text(
                    [
                        card.placeName ?? "",
                        "\(card.acceptedCount)/\(card.headcount) 人",
                        AppFormatters.relativeTime(card.createdAt)
                    ].filter { !$0.isEmpty }.joined(separator: " · ")
                )
                .font(.system(size: 11))
                .foregroundColor(AppTheme.tertiaryText)
                .lineLimit(1)
                if let desc = card.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .cardSurface()
        .contentShape(Rectangle())
    }
}
