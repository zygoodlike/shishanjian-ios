import SwiftUI

@MainActor
struct MyInterestsView: View {
    let onBack: () -> Void
    let onOpenCard: (Int64) -> Void
    let onOpenChat: (Int64, String?) -> Void
    let onGoHall: () -> Void

    @StateObject private var vm = MyInterestsViewModel()
    @State private var withdrawTarget: Interest?

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar("我的意向", onBack: onBack)
            if vm.loading {
                SkeletonList(rows: 3, rowHeight: 110)
                Spacer()
            } else if let error = vm.error, vm.interests.isEmpty {
                Spacer()
                ErrorStateView(message: error) { Task { await vm.load() } }
                Spacer()
            } else if vm.interests.isEmpty {
                EmptyStateView(
                    title: "还没有表达过意向",
                    subtitle: "去大厅看看，有没有想一起的人",
                    actionTitle: "去大厅",
                    action: onGoHall
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
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
        .confirmationDialog(
            "撤回这条意向？",
            isPresented: Binding(
                get: { withdrawTarget != nil },
                set: { if !$0 { withdrawTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: withdrawTarget
        ) { interest in
            Button("撤回", role: .destructive) {
                withdrawTarget = nil
                Task { await vm.withdraw(id: interest.id) }
            }
            Button("取消", role: .cancel) { withdrawTarget = nil }
        } message: { _ in
            Text("撤回后对方将看不到你的意向，之后仍可重新表达。")
        }
    }

    private func interestCard(_ interest: Interest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(interest.cardTitle ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.ink)
                    .lineLimit(1)
                Spacer()
                Text(AppFormatters.interestStatusLabel(interest.status))
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.secondaryText)
            }
            if let note = interest.note, !note.isEmpty {
                Text("「\(note)」")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.secondaryText)
                    .lineLimit(2)
            }
            HStack {
                Text(AppFormatters.relativeTime(interest.createdAt))
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.tertiaryText)
                Spacer()
                SecondaryButton(title: "查看需求") {
                    onOpenCard(interest.cardId)
                }
                if interest.status == 0 {
                    SecondaryButton(title: "撤回") {
                        withdrawTarget = interest
                    }
                }
                if interest.status == 1, let conversationId = interest.conversationId {
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
