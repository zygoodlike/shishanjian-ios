import SwiftUI

@MainActor
struct ReceivedInterestsView: View {
    let onBack: () -> Void
    let onOpenCard: (Int64) -> Void
    let onOpenChat: (Int64, String?) -> Void
    let onOpenUser: (Int64) -> Void

    @StateObject private var vm = ReceivedInterestsViewModel()

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar("收到的意向", onBack: onBack)
            if vm.loading {
                SkeletonList(rows: 3, rowHeight: 130, showAvatar: true)
                Spacer()
            } else if let error = vm.error, vm.interests.isEmpty {
                Spacer()
                ErrorStateView(message: error) { Task { await vm.load() } }
                Spacer()
            } else if vm.interests.isEmpty {
                EmptyStateView(
                    title: "还没有收到意向",
                    subtitle: "把需求发到大厅，等同学来回应"
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if let error = vm.error {
                            StatusBanner(text: error, danger: true)
                        }
                        ForEach(vm.interests) { interest in
                            interestCard(interest)
                        }
                    }
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.vertical, 8)
                }
                .refreshable { await vm.load(manual: true) }
            }
        }
        .appBackground()
        .task { await vm.loadIfStale() }
    }

    private func interestCard(_ interest: Interest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AvatarBlock(
                    userId: interest.userId,
                    name: interest.nickname,
                    imageURL: interest.avatar,
                    size: 38
                )
                .onTapGesture { onOpenUser(interest.userId) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(interest.nickname ?? "")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.ink)
                        .lineLimit(1)
                        .onTapGesture { onOpenUser(interest.userId) }
                    Text(AppFormatters.relativeTime(interest.createdAt))
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.tertiaryText)
                }
                Spacer()
                Text(AppFormatters.interestStatusLabel(interest.status))
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.secondaryText)
            }
            Button {
                onOpenCard(interest.cardId)
            } label: {
                Text(interest.cardTitle ?? "")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.secondaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            if let note = interest.note, !note.isEmpty {
                Text("「\(note)」")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.ink)
                    .lineLimit(2)
            }
            HStack {
                SecondaryButton(title: "查看需求") {
                    onOpenCard(interest.cardId)
                }
                Spacer()
                if interest.status == 0 {
                    SecondaryButton(
                        title: "忽略",
                        enabled: vm.actionId != interest.id
                    ) {
                        Task { await vm.ignore(id: interest.id) }
                    }
                    PrimaryButton(
                        title: "同意",
                        loading: vm.actionId == interest.id,
                        enabled: vm.actionId != interest.id,
                        fillWidth: false
                    ) {
                        Task {
                            if let conversationId = await vm.accept(id: interest.id) {
                                onOpenChat(conversationId, interest.cardTitle)
                            }
                        }
                    }
                } else if interest.status == 1, let conversationId = interest.conversationId {
                    PrimaryButton(title: "去聊天", fillWidth: false) {
                        onOpenChat(conversationId, interest.cardTitle)
                    }
                }
            }
        }
        .padding(16)
        .cardSurface()
    }
}

@MainActor
struct ReceivedCommentsView: View {
    let onBack: () -> Void
    let onOpenCard: (Int64) -> Void
    let onOpenUser: (Int64) -> Void

    @StateObject private var vm = ReceivedCommentsViewModel()

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar("收到的评论", onBack: onBack)
            if vm.loading {
                SkeletonList(rows: 3, rowHeight: 110, showAvatar: true)
                Spacer()
            } else if let error = vm.error, vm.comments.isEmpty {
                Spacer()
                ErrorStateView(message: error) { Task { await vm.load() } }
                Spacer()
            } else if vm.comments.isEmpty {
                EmptyStateView(
                    title: "还没有收到评论",
                    subtitle: "发布的需求有人评论后，会出现在这里"
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if let error = vm.error {
                            StatusBanner(text: error, danger: true)
                        }
                        ForEach(vm.comments) { comment in
                            commentCard(comment)
                                .onTapGesture { onOpenUser(comment.userId) }
                        }
                    }
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.vertical, 8)
                }
                .refreshable { await vm.load(manual: true) }
            }
        }
        .appBackground()
        .task { await vm.loadIfStale() }
    }

    private func commentCard(_ comment: ReceivedComment) -> some View {
        Button {
            onOpenCard(comment.cardId)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    AvatarBlock(
                        userId: comment.userId,
                        name: comment.nickname,
                        imageURL: comment.avatar,
                        size: 34
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(comment.nickname ?? "")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.ink)
                            if let replyTo = comment.replyToNickname, !replyTo.isEmpty {
                                Text("回复 @\(replyTo)")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.secondaryText)
                            }
                        }
                        Text(AppFormatters.relativeTime(comment.createdAt))
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.tertiaryText)
                    }
                    Spacer()
                }
                Text(comment.content ?? "")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.ink)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("评论于「\(comment.cardTitle ?? "")」")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.tertiaryText)
                    .lineLimit(1)
            }
            .padding(16)
            .cardSurface()
        }
        .buttonStyle(.plain)
    }
}
