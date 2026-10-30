import SwiftUI
import PhotosUI
import UIKit

@MainActor
struct OnboardingView: View {
    let onDone: () -> Void

    private let services = AppServices.shared
    @State private var nickname = ""
    @State private var selectedScenes = Set<String>()
    @State private var avatarData: Data?
    @State private var pickerItem: PhotosPickerItem?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 48)
            Text("先认识一下你")
                .font(.system(size: 28, weight: .heavy))
                .foregroundColor(AppTheme.ink)
            Text("昵称和兴趣都可以随时修改")
                .font(.system(size: 14))
                .foregroundColor(AppTheme.secondaryText)
                .padding(.top, 8)
            Spacer().frame(height: 28)

            PhotosPicker(selection: $pickerItem, matching: .images) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(AppTheme.soft)
                        .frame(width: 76, height: 76)
                    if let avatarData, let image = UIImage(data: avatarData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 76, height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    } else {
                        Text("选填")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.tertiaryText)
                    }
                }
            }
            .buttonStyle(.plain)

            FieldLabel(text: "昵称")
                .padding(.top, 24)
            AuthField(text: $nickname, placeholder: "2–12 个字")
                .padding(.top, 8)
            Text("昵称是站内署名，可随时修改")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.tertiaryText)
                .padding(.top, 6)

            FieldLabel(text: "你对什么感兴趣？")
                .padding(.top, 24)
            Text("最多选 3 个")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.tertiaryText)
                .padding(.top, 4)
            FlowLayout(spacing: 8) {
                ForEach(appScenes) { scene in
                    let active = selectedScenes.contains(scene.key)
                    let full = selectedScenes.count >= 3 && !active
                    Button {
                        if active {
                            selectedScenes.remove(scene.key)
                        } else if selectedScenes.count < 3 {
                            selectedScenes.insert(scene.key)
                        }
                    } label: {
                        Text(scene.label)
                            .font(.system(size: 14))
                            .foregroundColor(active ? .white : (full ? AppTheme.tertiaryText : AppTheme.secondaryText))
                            .padding(.horizontal, 18)
                            .frame(height: 40)
                            .background(Capsule().fill(active ? AppTheme.ink : (full ? AppTheme.soft.opacity(0.5) : Color.white)))
                            .overlay(Capsule().stroke(active ? AppTheme.ink : AppTheme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(full)
                }
            }
            .padding(.top, 12)

            if let error {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.danger)
                    .padding(.top, 14)
            }

            Spacer()
            PrimaryButton(title: "进入狮山见", loading: loading) { finish(skip: false) }
            Button {
                finish(skip: true)
            } label: {
                Text("跳过")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .appBackground()
        .onAppear {
            if nickname.isEmpty {
                nickname = services.auth.session?.nickname ?? ""
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    avatarData = data
                    do {
                        _ = try await services.repository.uploadAvatar(data)
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            }
        }
    }

    private func finish(skip: Bool) {
        loading = true
        error = nil
        Task {
            do {
                if !skip {
                    _ = try await services.api.updateProfile(
                        UpdateProfileRequest(nickname: nickname.isEmpty ? nil : nickname, bio: nil)
                    )
                    _ = try await services.api.updateScenes(ScenesRequest(scenes: Array(selectedScenes)))
                    services.auth.updateNickname(nickname.isEmpty ? nil : nickname)
                }
                services.auth.consumeJustRegistered()
                loading = false
                onDone()
            } catch {
                loading = false
                self.error = error.localizedDescription
            }
        }
    }
}
