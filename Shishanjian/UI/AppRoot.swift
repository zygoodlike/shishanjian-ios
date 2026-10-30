import Combine
import SwiftUI
import UIKit

enum AppTab: Hashable {
    case hall
    case create
    case chat
    case me
}

struct ConversationRoute: Hashable {
    let id: Int64
    let title: String?
    let cardTitle: String?
    let cardId: Int64?
    let otherUserId: Int64?
    let status: Int
}

enum AppRoute: Hashable {
    case login
    case register
    case resetPassword
    case onboarding
    case card(Int64)
    case user(Int64)
    case conversation(ConversationRoute)
    case myCards
    case myInterests
    case receivedInterests
    case receivedComments
    case feedback
    case myFeedback
    case publishResult
    case settings
    case devices
    case deleteAccount
}

@MainActor
struct AppRoot: View {
    @ObservedObject private var auth = AppServices.shared.auth
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [AppRoute] = []
    @State private var tab: AppTab = .hall

    var body: some View {
        NavigationStack(path: $path) {
            TabView(selection: $tab) {
                HallView(
                    loggedIn: auth.isLoggedIn,
                    onLogin: { path.append(.login) },
                    onOpenCard: { path.append(.card($0)) },
                    onOpenUser: { path.append(.user($0)) },
                    onCreate: { tab = .create }
                )
                .tabItem { Label("大厅", systemImage: "house") }
                .tag(AppTab.hall)

                Group {
                    if auth.isLoggedIn {
                        CreateCardView(
                            onBack: { tab = .hall },
                            onPublishing: {
                                tab = .hall
                                path.append(.publishResult)
                            }
                        )
                    } else {
                        GuestGateView(
                            title: "登录后才能发布",
                            subtitle: "用学校邮箱确认校内身份，再发布你的第一张需求。",
                            onLogin: { path.append(.login) }
                        )
                    }
                }
                .tabItem { Label("发布", systemImage: "plus.circle") }
                .tag(AppTab.create)

                Group {
                    if auth.isLoggedIn {
                        ChatListView(
                            onOpenConversation: { conversation in
                                path.append(.conversation(
                                    ConversationRoute(
                                        id: conversation.id,
                                        title: conversation.otherNickname,
                                        cardTitle: conversation.cardTitle,
                                        cardId: conversation.cardId,
                                        otherUserId: conversation.otherUserId,
                                        status: conversation.status
                                    )
                                ))
                            },
                            onOpenUser: { path.append(.user($0)) },
                            onGoHall: { tab = .hall }
                        )
                    } else {
                        GuestGateView(
                            title: "登录后查看消息",
                            subtitle: "表达意向并被同意后，就可以在这里和对方聊天。",
                            onLogin: { path.append(.login) }
                        )
                    }
                }
                .tabItem { Label("消息", systemImage: "bubble.left") }
                .tag(AppTab.chat)

                Group {
                    if auth.isLoggedIn {
                        MeView(
                            onOpenCards: { path.append(.myCards) },
                            onOpenInterests: { path.append(.myInterests) },
                            onOpenReceivedInterests: { path.append(.receivedInterests) },
                            onOpenReceivedComments: { path.append(.receivedComments) },
                            onOpenFeedback: { path.append(.feedback) },
                            onOpenMyFeedback: { path.append(.myFeedback) },
                            onOpenSettings: { path.append(.settings) },
                            onOpenDevices: { path.append(.devices) }
                        )
                    } else {
                        GuestGateView(
                            title: "登录后管理资料",
                            subtitle: "登录后可以编辑昵称头像、查看需求和登录设备。",
                            onLogin: { path.append(.login) }
                        )
                    }
                }
                .tabItem { Label("我的", systemImage: "person") }
                .tag(AppTab.me)
            }
            .tint(AppTheme.accentDeep)
            .animation(.snappy(duration: 0.22), value: tab)
            .onChange(of: tab) { _, _ in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AppRoute.self) { route in
                destination(route)
                    .toolbar(.hidden, for: .navigationBar)
                    .toolbar(.hidden, for: .tabBar)
            }
        }
        .preferredColorScheme(.light)
        .onChange(of: auth.session?.token) { _, token in
            if token == nil {
                path = auth.consumeJustLoggedOut() ? [.login] : []
                tab = .hall
                AppServices.shared.realtime.setActive(false)
                ChatCache.clearAll()
                ApiDiskCache.clearAll()
                ProfileCache.shared.clear()
            } else if scenePhase == .active {
                AppServices.shared.realtime.setActive(true)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // 只有真正进入后台才断开；下拉通知栏、控制中心、来电等 inactive 不断开，避免反复重连补拉
            switch phase {
            case .active:
                if auth.isLoggedIn { AppServices.shared.realtime.setActive(true) }
            case .background:
                AppServices.shared.realtime.setActive(false)
            default:
                break
            }
        }
        .onAppear {
            if let session = auth.session {
                ProfileCache.shared.update(
                    userId: session.userId,
                    nickname: session.nickname,
                    avatar: session.avatarKey
                )
            }
            if scenePhase == .active && auth.isLoggedIn {
                AppServices.shared.realtime.setActive(true)
            }
        }
        .onChange(of: auth.session) { _, session in
            if let session {
                ProfileCache.shared.update(
                    userId: session.userId,
                    nickname: session.nickname,
                    avatar: session.avatarKey
                )
            } else {
                ProfileCache.shared.clear()
            }
        }
        .onAppear {
            if auth.session?.justRegistered == true, path.isEmpty {
                path = [.onboarding]
            }
        }
        .task {
            await AppLimits.shared.refresh(api: AppServices.shared.api)
        }
        .onReceive(AppServices.shared.realtime.events.receive(on: DispatchQueue.main)) { event in
            if case .cardStatusChanged(_, let title, let status, let statusLabel) = event {
                let detail: String
                switch status {
                case 1: detail = "已通过审核，现在可以在大厅看到"
                case 5: detail = "未通过审核，可以修改后重新发布"
                default: detail = statusLabel ?? "状态已更新"
                }
                let cardTitle = (title?.isEmpty == false) ? title! : "你的需求"
                AppNoticeCenter.shared.message(
                    title: "需求状态更新",
                    message: "「(cardTitle)」(detail)"
                )
                return
            }
            guard scenePhase == .active,
                  case .newMessage(let convId, let message, let senderName, _) = event,
                  message.senderId != auth.userId,
                  convId != currentConversationId else { return }
            AppNoticeCenter.shared.message(
                title: senderName?.isEmpty == false ? senderName : "新消息",
                message: message.previewText
            )
        }
        .overlay(alignment: .top) {
            AppNoticeBanner()
        }
    }

    private var currentConversationId: Int64? {
        if case .conversation(let route) = path.last {
            return route.id
        }
        return nil
    }

    @ViewBuilder
    private func destination(_ route: AppRoute) -> some View {
        switch route {
        case .login:
            LoginView(
                onGoRegister: { path.append(.register) },
                onGoReset: { path.append(.resetPassword) },
                onLoggedIn: {}
            )
        case .resetPassword:
            ResetPasswordView(
                onBack: { path.removeLast() },
                onReset: {
                    AppNoticeCenter.shared.message(
                        title: "密码已重置",
                        message: "请使用新密码重新登录"
                    )
                    path = [.login]
                }
            )
        case .register:
            RegisterView(
                onGoLogin: { path.removeLast() },
                onRegistered: { path = [.onboarding] }
            )
        case .onboarding:
            OnboardingView {
                path = []
                tab = .hall
            }
        case .card(let id):
            CardDetailView(
                cardId: id,
                currentUserId: auth.userId,
                loggedIn: auth.isLoggedIn,
                onRequireLogin: { path.append(.login) },
                onBack: { path.removeLast() },
                onOpenCard: { path.append(.card($0)) },
                onOpenChat: { convId, title, cardTitle, cardId in
                    guard let convId else { return }
                    path.append(.conversation(
                        ConversationRoute(
                            id: convId,
                            title: title,
                            cardTitle: cardTitle,
                            cardId: cardId,
                            otherUserId: nil,
                            status: 0
                        )
                    ))
                },
                onOpenUser: { path.append(.user($0)) },
                onOpenFeedback: { path.append(.feedback) }
            )
        case .user(let userId):
            UserProfileView(
                userId: userId,
                onBack: { path.removeLast() },
                onOpenCard: { path.append(.card($0)) },
                onOpenChat: { convId in
                    path.append(.conversation(
                        ConversationRoute(
                            id: convId,
                            title: nil,
                            cardTitle: nil,
                            cardId: nil,
                            otherUserId: userId,
                            status: 0
                        )
                    ))
                }
            )
        case .conversation(let route):
            ChatDetailView(
                convId: route.id,
                title: route.title,
                cardTitle: route.cardTitle,
                cardId: route.cardId,
                otherUserId: route.otherUserId,
                initialStatus: route.status,
                currentUserId: auth.userId,
                onBack: { path.removeLast() },
                onOpenCard: { path.append(.card($0)) },
                onOpenUser: { path.append(.user($0)) }
            )
        case .myCards:
            MyCardsView(
                onBack: { path.removeLast() },
                onOpenCard: { path.append(.card($0)) },
                onCreate: {
                    path = []
                    tab = .create
                }
            )
        case .myInterests:
            MyInterestsView(
                onBack: { path.removeLast() },
                onOpenCard: { path.append(.card($0)) },
                onOpenChat: { convId, cardTitle in
                    path.append(.conversation(
                        ConversationRoute(
                            id: convId,
                            title: nil,
                            cardTitle: cardTitle,
                            cardId: nil,
                            otherUserId: nil,
                            status: 0
                        )
                    ))
                },
                onGoHall: {
                    path = []
                    tab = .hall
                }
            )
        case .receivedInterests:
            ReceivedInterestsView(
                onBack: { path.removeLast() },
                onOpenCard: { path.append(.card($0)) },
                onOpenChat: { convId, cardTitle in
                    path.append(.conversation(
                        ConversationRoute(
                            id: convId,
                            title: nil,
                            cardTitle: cardTitle,
                            cardId: nil,
                            otherUserId: nil,
                            status: 0
                        )
                    ))
                },
                onOpenUser: { path.append(.user($0)) }
            )
        case .receivedComments:
            ReceivedCommentsView(
                onBack: { path.removeLast() },
                onOpenCard: { path.append(.card($0)) },
                onOpenUser: { path.append(.user($0)) }
            )
        case .feedback:
            FeedbackView(
                onBack: { path.removeLast() },
                onOpenMyFeedback: { path.append(.myFeedback) }
            )
        case .myFeedback:
            MyFeedbackView(
                onBack: { path.removeLast() },
                onNewFeedback: { path.append(.feedback) }
            )
        case .publishResult:
            PublishResultView(
                onOpenCard: { path.append(.card($0)) },
                onOpenMyCards: {
                    path = [.myCards]
                    tab = .me
                },
                onBackToHall: {
                    path = []
                    tab = .hall
                },
                onEditAgain: {
                    path = []
                    tab = .create
                },
                onOpenFeedback: { path = [.feedback] }
            )
        case .settings:
            SettingsView(
                onBack: { path.removeLast() },
                onOpenDevices: { path.append(.devices) },
                onOpenDelete: { path.append(.deleteAccount) }
            )
        case .devices:
            DevicesView(onBack: { path.removeLast() })
        case .deleteAccount:
            DeleteAccountView(onBack: { path.removeLast() })
        }
    }
}
