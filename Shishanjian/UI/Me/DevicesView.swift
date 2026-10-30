import SwiftUI

@MainActor
struct DevicesView: View {
    let onBack: () -> Void

    @StateObject private var vm = DevicesViewModel()
    @State private var revokeTarget: DeviceSession?
    @State private var revokeAllConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar("登录设备", onBack: onBack)
            if vm.loading {
                SkeletonList(rows: 2, rowHeight: 72)
                Spacer()
            } else if let error = vm.error, vm.sessions.isEmpty {
                Spacer()
                ErrorStateView(message: error) { Task { await vm.load() } }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(vm.sessions) { session in
                            sessionRow(session)
                        }
                    }
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.vertical, 8)
                }
                Button {
                    revokeAllConfirm = true
                } label: {
                    Text("退出所有设备")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.danger)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.vertical, 10)
            }
        }
        .appBackground()
        .task { await vm.load() }
        .alert("下线这台设备？", isPresented: Binding(
            get: { revokeTarget != nil },
            set: { if !$0 { revokeTarget = nil } }
        )) {
            Button("取消", role: .cancel) { revokeTarget = nil }
            Button("下线", role: .destructive) {
                if let target = revokeTarget {
                    Task { await vm.revoke(sid: target.sid) }
                }
                revokeTarget = nil
            }
        } message: {
            Text("下线后该设备需要重新登录。")
        }
        .confirmationDialog("退出所有设备？", isPresented: $revokeAllConfirm, titleVisibility: .visible) {
            Button("全部退出", role: .destructive) {
                Task { await vm.revokeAll() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所有设备都会退出登录，包括当前设备。")
        }
    }

    private func sessionRow(_ session: DeviceSession) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(platformName(session.platform))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.ink)
                    if session.current {
                        Text("当前设备")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.trustGreen)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AppTheme.trustSurface))
                    }
                }
                Text("\(shortDevice(session.deviceId)) · \(AppFormatters.relativeTime(session.lastActiveAt))")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.secondaryText)
            }
            Spacer()
            if !session.current {
                SecondaryButton(title: "下线") {
                    revokeTarget = session
                }
            }
        }
        .padding(16)
        .cardSurface()
    }

    private func platformName(_ platform: String?) -> String {
        switch platform {
        case "ios": return "iPhone"
        case "android": return "Android"
        case "miniprogram": return "微信小程序"
        case "admin": return "管理后台"
        default: return "未知设备"
        }
    }

    private func shortDevice(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "未知设备" }
        return String(value.prefix(12))
    }
}
