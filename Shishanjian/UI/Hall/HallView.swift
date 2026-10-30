import SwiftUI

@MainActor
struct HallView: View {
    let loggedIn: Bool
    let onLogin: () -> Void
    let onOpenCard: (Int64) -> Void
    let onOpenUser: (Int64) -> Void
    let onCreate: () -> Void

    @StateObject private var vm = HallViewModel()
    @State private var searchOpen = false
    @State private var keyword = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            if !searchOpen {
                Button {
                    searchOpen = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15))
                            .foregroundColor(AppTheme.tertiaryText)
                        Text("搜索需求、场景或同学")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.tertiaryText)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(Capsule().fill(AppTheme.surface))
                    .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.bottom, 10)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    // 场景筛选单行横向滚动，不换行挤压列表
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterPill(title: "全部", selected: vm.scene == nil) {
                                Task { await vm.selectScene(nil) }
                            }
                            ForEach(appScenes) { scene in
                                FilterPill(title: scene.label, selected: vm.scene == scene.key) {
                                    Task { await vm.selectScene(scene.key) }
                                }
                            }
                        }
                        .padding(.horizontal, AppTheme.pagePadding)
                    }

                    Text("最新发布")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AppTheme.ink)
                        .padding(.horizontal, AppTheme.pagePadding)
                        .padding(.top, 6)

                    if vm.loading && vm.cards.isEmpty {
                        loadingCards
                    } else if let error = vm.error, vm.cards.isEmpty {
                        ErrorStateView(message: error) {
                            Task { await vm.refresh() }
                        }
                    } else if vm.cards.isEmpty {
                        EmptyStateView(
                            title: "今天还没有需求",
                            subtitle: "发一张，看看有没有人一起",
                            actionTitle: "发布需求",
                            action: onCreate
                        )
                    } else {
                        ForEach(vm.cards) { card in
                            NeedCardView(card: card, onTap: { onOpenCard(card.id) }, onOpenUser: { onOpenUser($0) })
                                .padding(.horizontal, AppTheme.pagePadding)
                                .onAppear {
                                    if card.id == vm.cards.last?.id {
                                        Task { await vm.loadMore() }
                                    }
                                }
                        }
                        if vm.loadingMore {
                            Text("加载中…")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.tertiaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .refreshable {
                await vm.refresh(manual: true)
            }
        }
        .appBackground()
        // 只在首次进入和登录状态变化时请求；切 tab 回来不刷新，用户下拉才刷新
        .task { await vm.loadIfNeeded() }
        .onChange(of: loggedIn) { _, _ in
            Task { await vm.refresh() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if searchOpen {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(AppTheme.tertiaryText)
                    TextField("搜索需求", text: $keyword)
                        .font(.system(size: 14))
                        .submitLabel(.search)
                        .onSubmit {
                            Task { await vm.search(keyword) }
                        }
                    Button {
                        searchOpen = false
                        keyword = ""
                        Task { await vm.search("") }
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(AppTheme.secondaryText)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("取消搜索")
                }
                .padding(.leading, 12)
                .frame(height: 44)
                .background(Capsule().fill(AppTheme.soft))
                .overlay(Capsule().stroke(AppTheme.line, lineWidth: 1))
            } else {
                LogoView(size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("狮山见")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundColor(AppTheme.ink)
                    Text("看看今天谁需要你")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.tertiaryText)
                }
                Spacer()
                if !loggedIn {
                    Button(action: onLogin) {
                        Text("登录")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.accentDeep)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.vertical, 12)
    }

    private var loadingCards: some View {
        SkeletonList(rows: 3, rowHeight: 132)
    }
}
