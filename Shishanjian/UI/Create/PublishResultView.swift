import SwiftUI

/// 发布后的独立结果页。上传和 AI 审核可能要几十秒，
/// 用户可以先离开，任务在 AppServices 上继续执行。
@MainActor
struct PublishResultView: View {
    let onOpenCard: (Int64) -> Void
    let onOpenMyCards: () -> Void
    let onBackToHall: () -> Void
    let onEditAgain: () -> Void
    let onOpenFeedback: () -> Void

    @ObservedObject private var publisher = AppServices.shared.publisher

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar("发布结果", onBack: onBackToHall)
            Spacer()
            content
                .padding(.horizontal, 32)
            Spacer()
        }
        .appBackground()
    }

    @ViewBuilder
    private var content: some View {
        switch publisher.task.phase {
        case .uploading, .submitting:
            runningState
        case .published:
            publishedState
        case .pendingReview:
            pendingState
        case .failed:
            failedState
        case .idle:
            VStack(spacing: 20) {
                Text("没有正在处理的发布")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.secondaryText)
                SecondaryButton(title: "返回大厅", action: onBackToHall)
            }
        }
    }

    private var runningState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(AppTheme.accent)
                .scaleEffect(1.4)
                .padding(.bottom, 10)
            Text("正在提交")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppTheme.ink)
            Text(runningHint)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
            Text("可以先返回大厅，出结果后会自动提示")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
    }

    private var runningHint: String {
        let task = publisher.task
        if task.phase == .uploading, task.total > 0 {
            return "正在上传图片 \(task.uploaded + 1)/\(task.total)，审核可能需要几十秒"
        }
        return "正在进行内容审核，审核可能需要几十秒"
    }

    private var publishedState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(AppTheme.accent)
                .padding(.bottom, 8)
            Text("发布成功")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppTheme.ink)
            Text("你的需求已经出现在大厅，可以等同学来表达了。")
                .font(.system(size: 14))
                .foregroundColor(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 18)
            if let cardId = publisher.task.cardId {
                PrimaryButton(title: "查看需求") {
                    onOpenCard(cardId)
                }
            }
            SecondaryButton(title: "返回大厅", action: onBackToHall)
        }
    }

    private var pendingState: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(AppTheme.soft)
                    .frame(width: 58, height: 58)
                Image(systemName: "hourglass")
                    .font(.system(size: 26))
                    .foregroundColor(AppTheme.accent)
            }
            .padding(.bottom, 8)
            Text("已提交，等待复核")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppTheme.ink)
            Text(publisher.task.message ?? "内容正在等待人工复核，通过后会出现在大厅。")
                .font(.system(size: 14))
                .foregroundColor(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 18)
            PrimaryButton(title: "查看我的需求", action: onOpenMyCards)
            SecondaryButton(title: "返回大厅", action: onBackToHall)
        }
    }

    private var failedState: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 52))
                .foregroundColor(AppTheme.danger)
                .padding(.bottom, 8)
            Text(publisher.task.rejected ? "内容未通过审核" : "发布失败")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppTheme.ink)
            Text(publisher.task.message ?? "请稍后再试")
                .font(.system(size: 14))
                .foregroundColor(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 18)
            PrimaryButton(title: publisher.task.rejected ? "去反馈" : "返回修改") {
                if publisher.task.rejected {
                    onOpenFeedback()
                } else {
                    onEditAgain()
                }
            }
            SecondaryButton(title: "返回大厅", action: onBackToHall)
        }
    }
}
