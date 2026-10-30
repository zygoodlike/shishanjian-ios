import SwiftUI

@MainActor
struct ChatListView: View {
    let onOpenConversation: (Conversation) -> Void
    let onOpenUser: (Int64) -> Void
    let onGoHall: () -> Void

    @StateObject private var vm = ChatListViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("消息")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundColor(AppTheme.ink)
                Spacer()
                RefreshButton {
                    Task { await vm.refresh(manual: true) }
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.vertical, 16)

            if vm.loading && vm.conversations.isEmpty {
                SkeletonList(rows: 4, rowHeight: 72, showAvatar: true)
                Spacer()
            } else if let error = vm.error, vm.conversations.isEmpty {
                Spacer()
                ErrorStateView(message: error) {
                    Task { await vm.refresh() }
                }
                Spacer()
            } else if vm.conversations.isEmpty {
                EmptyStateView(
                    title: "还没有消息",
                    subtitle: "表达意向并被同意后，就可以在这里聊天",
                    actionTitle: "去大厅",
                    action: onGoHall
                )
                Spacer()
            } else {
                ScrollView {
                    // 参照 QQ：整块白底平铺列表，分割线从头像右侧开始
                    LazyVStack(spacing: 0) {
                        ForEach(Array(vm.conversations.enumerated()), id: \.element.id) { index, conversation in
                            Button {
                                onOpenConversation(conversation)
                            } label: {
                                conversationRow(conversation, showDivider: index < vm.conversations.count - 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(AppTheme.surface)
                    .padding(.bottom, 20)
                }
                .refreshable {
                    await vm.refresh(manual: true)
                }
            }
        }
        .appBackground()
        .task { await vm.loadIfNeeded() }
    }

    private func conversationRow(_ conversation: Conversation, showDivider: Bool) -> some View {
        HStack(spacing: 12) {
            AvatarBlock(
                userId: conversation.otherUserId ?? 0,
                name: conversation.otherNickname,
                imageURL: conversation.otherAvatar,
                size: 48
            )
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
            .onTapGesture {
                if let id = conversation.otherUserId { onOpenUser(id) }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conversation.otherNickname ?? "")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.ink)
                        .lineLimit(1)
                    Spacer()
                    Text(AppFormatters.relativeTime(conversation.lastMsgAt))
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.tertiaryText)
                }
                HStack {
                    Text(conversation.status != 0 ? "[会话已结束]" : (conversation.lastMessage ?? ""))
                        .font(.system(size: 13))
                        .foregroundColor(conversation.status != 0 ? AppTheme.tertiaryText : AppTheme.secondaryText)
                        .lineLimit(1)
                    Spacer()
                    if conversation.unread > 0 {
                        Text(conversation.unread > 99 ? "99+" : "\(conversation.unread)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Capsule().fill(AppTheme.danger))
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                if showDivider {
                    Rectangle()
                        .fill(AppTheme.line)
                        .frame(height: 1)
                }
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .frame(height: 72)
        .contentShape(Rectangle())
    }
}
