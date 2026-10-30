import SwiftUI

@MainActor
struct CaptchaSheet: View {
    let purpose: String
    let onVerified: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var challenge: CaptchaChallenge?
    @State private var loading = true
    @State private var verifying = false
    @State private var error: String?
    @State private var imageError: String?
    @State private var backgroundReady = false
    @State private var pieceReady = false
    @State private var fraction: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("请完成验证")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(AppTheme.ink)
                    Text("拖动滑块完成拼图")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.secondaryText)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(AppTheme.secondaryText)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 16)

            if loading {
                placeholder
            } else if let challenge {
                puzzle(challenge)
            } else {
                VStack(spacing: 10) {
                    placeholder
                    Text(error ?? "题目加载失败")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.secondaryText)
                    Button("重试") { Task { await loadChallenge() } }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.ink)
                }
            }

            if let error, challenge != nil {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.danger)
                    .padding(.top, 10)
            }

            PrimaryButton(
                title: "验证并发送",
                loading: verifying,
                enabled: challenge != nil && backgroundReady && pieceReady && fraction > 0,
                action: submit
            )
            .padding(.top, 18)
            Button {
                Task { await loadChallenge() }
            } label: {
                Text("换一张")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 24)
        .presentationDetents([.large])
        .task { await loadChallenge() }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(AppTheme.soft)
            .aspectRatio(2, contentMode: .fit)
            .overlay(
                Text(loading ? "正在加载题目…" : "题目加载失败")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.tertiaryText)
            )
    }

    private func puzzle(_ challenge: CaptchaChallenge) -> some View {
        let ready = backgroundReady && pieceReady
        return VStack(spacing: 16) {
            GeometryReader { geo in
                let imageWidth = geo.size.width
                let imageHeight = imageWidth / 2
                let pieceWidth = imageWidth * 48 / 320
                let pieceOffsetX = fraction * (imageWidth - pieceWidth)
                let pieceOffsetY = CGFloat(challenge.y) / 160 * imageHeight
                ZStack(alignment: .topLeading) {
                    AsyncImage(url: ApiConfig.absolute(challenge.background)) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                                .onAppear { backgroundReady = true }
                        } else {
                            AppTheme.soft
                                .onAppear {
                                    if phase.error != nil {
                                        imageError = "验证图片加载失败，请重试"
                                    }
                                }
                        }
                    }
                    .frame(width: imageWidth, height: imageHeight)
                    .clipped()

                    AsyncImage(url: ApiConfig.absolute(challenge.piece)) { phase in
                        if let image = phase.image {
                            image.resizable()
                                .onAppear { pieceReady = true }
                        } else {
                            Color.clear
                                .onAppear {
                                    if phase.error != nil {
                                        imageError = "验证图片加载失败，请重试"
                                    }
                                }
                        }
                    }
                    .frame(width: pieceWidth, height: pieceWidth)
                    .offset(x: pieceOffsetX, y: pieceOffsetY)

                    if !ready {
                        AppTheme.soft.opacity(0.92)
                            .overlay(
                                Text(imageError ?? "正在加载验证图片…")
                                    .font(.system(size: 13))
                                    .foregroundColor(AppTheme.tertiaryText)
                            )
                    }
                }
            }
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if ready {
                GeometryReader { geo in
                    let trackWidth = geo.size.width
                    let knob: CGFloat = 44
                    let maxOffset = max(1, trackWidth - knob)
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppTheme.soft)
                        if fraction <= 0.01 {
                            Text("向右拖动")
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.tertiaryText)
                                .frame(maxWidth: .infinity)
                        }
                        Circle()
                            .fill(AppTheme.accentDeep)
                            .frame(width: knob, height: knob)
                            .overlay(
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                            .offset(x: fraction * maxOffset)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        fraction = min(max(0, value.location.x / maxOffset), 1)
                                    }
                                    .onEnded { _ in submit() }
                            )
                    }
                    .frame(height: 52)
                    .clipShape(Capsule())
                }
                .frame(height: 52)
            } else {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(AppTheme.soft)
                    .frame(height: 52)
                    .overlay(
                        Text("正在加载验证图片…")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.tertiaryText)
                    )
            }
        }
    }

    private func loadChallenge() async {
        loading = true
        error = nil
        imageError = nil
        backgroundReady = false
        pieceReady = false
        challenge = nil
        fraction = 0
        do {
            challenge = try await AppServices.shared.api.captchaChallenge(
                CaptchaChallengeRequest(purpose: purpose)
            )
        } catch {
            challenge = nil
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func submit() {
        guard let challenge, !verifying else { return }
        let x = Int(fraction * CGFloat(challenge.width - 48))
        verifying = true
        error = nil
        Task {
            do {
                let result = try await AppServices.shared.api.captchaVerify(
                    CaptchaVerifyRequest(
                        challengeId: challenge.challengeId,
                        x: min(max(0, x), challenge.width - 48),
                        track: [x]
                    )
                )
                verifying = false
                if let ticket = result.ticket, !ticket.isEmpty {
                    onVerified(ticket)
                    dismiss()
                } else {
                    error = "验证失败，请重试"
                    fraction = 0
                }
            } catch {
                verifying = false
                self.error = error.localizedDescription
                fraction = 0
            }
        }
    }
}
