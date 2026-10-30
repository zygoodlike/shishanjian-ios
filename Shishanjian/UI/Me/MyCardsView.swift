import SwiftUI

@MainActor
struct MyCardsView: View {
    let onBack: () -> Void
    let onOpenCard: (Int64) -> Void
    let onCreate: () -> Void

    @StateObject private var vm = MyCardsViewModel()

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar("我的需求", onBack: onBack)
            HStack(spacing: 8) {
                FilterPill(title: "进行中", selected: vm.group == "active") {
                    Task { await vm.load("active") }
                }
                FilterPill(title: "审核中", selected: vm.group == "review") {
                    Task { await vm.load("review") }
                }
                FilterPill(title: "已隐藏", selected: vm.group == "paused") {
                    Task { await vm.load("paused") }
                }
                FilterPill(title: "已结束", selected: vm.group == "closed") {
                    Task { await vm.load("closed") }
                }
                Spacer()
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.vertical, 6)

            if vm.loading {
                SkeletonList(rows: 3, rowHeight: 120)
                Spacer()
            } else if let error = vm.error {
                Spacer()
                ErrorStateView(message: error) { Task { await vm.load(vm.group) } }
                Spacer()
            } else if vm.cards.isEmpty {
                EmptyStateView(
                    title: "还没有需求",
                    subtitle: "发一张，看看有没有人一起",
                    actionTitle: "发布需求",
                    action: onCreate
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(vm.cards) { card in
                            NeedCardView(card: card, onTap: { onOpenCard(card.id) })
                        }
                    }
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.vertical, 8)
                }
            }
        }
        .appBackground()
        .task { await vm.loadIfStale() }
    }
}
