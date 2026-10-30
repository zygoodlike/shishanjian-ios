# 在 iPhone 上安装狮山见（不买开发者账号）

整条链路：

```
GitHub Actions（免费 macOS）编译出未签名 IPA
        ↓ 下载
Windows + Sideloadly（免费 Apple ID 签名）
        ↓ USB
iPhone 安装，7 天有效，到期重签
```

前置条件：

- iPhone 系统 **iOS 17 或更高**（工程 deployment target 是 17.0）。
- Windows 电脑装好 [iTunes](https://www.apple.com/itunes/download/win64)（苹果官网版，不要 Microsoft Store 版）和 [Sideloadly](https://sideloadly.io/)。
- 一个 Apple ID（免费即可，不需要开发者账号）。
- 一个 GitHub 账号（免费）。

---

## 1. 推送到 GitHub

在 GitHub 网页新建一个 **Public** 仓库，例如 `shishanjian-ios`（公开仓库的 macOS Actions 分钟数免费）。

在本目录执行（把 `<你的用户名>` 换掉）：

```bash
git init
git add .
git commit -m "feat: 狮山见 iOS 客户端"
git branch -M main
git remote add origin https://github.com/<你的用户名>/shishanjian-ios.git
git push -u origin main
```

如果没有配置 GitHub 凭据，先在本机执行一次 `gh auth login`（安装 GitHub CLI）或在 GitHub 网页用 “upload files” 直接上传整个目录。

## 2. 云端打包

1. 打开仓库的 **Actions** 标签。
2. 左侧选 **Build unsigned IPA** → 右侧 **Run workflow** → 再点绿色 **Run workflow**。
3. 等 5–15 分钟。第一次很可能编译报错，把失败的 log 发我，我改代码后再推。
4. 成功后进入这次运行，页面底部 **Artifacts** 下载 `Shishanjian-unsigned-ipa.zip`，解压得到 `Shishanjian-unsigned.ipa`。

## 3. 装到 iPhone

1. iPhone 用数据线连电脑，手机上点「信任此电脑」。
2. 打开 Sideloadly，iPhone 会自动出现在 `iDevice` 里。
3. 把 `Shishanjian-unsigned.ipa` 拖进 Sideloadly 的 IPA 框。
4. `Apple ID` 填你的 Apple ID，点 **Start**。
5. 弹窗输入 Apple ID 密码；如果开了双重认证，输入手机收到的 6 位验证码。
6. 安装完成后，iPhone 上打开 **设置 → 通用 → VPN 与设备管理**，点你的 Apple ID，选择 **信任**。
7. 回到桌面打开「狮山见」。

登录账号：

```
用户名：zyabc123
密码：  @Azm20050219
```

## 4. 七天到期怎么办

免费 Apple ID 签名的 App **7 天后会打不开**。不用重新编译，打开 Sideloadly，对同一个 IPA 再点一次 **Start** 重签即可，账号数据不会丢（Keychain 里的登录态一般也能保留）。

限制：

- 免费账号同时最多 3 个自签 App。
- 每周最多注册 10 个 App ID。
- 没有 APNs 推送；App 在前台时靠 WebSocket 实时收消息，退到后台收不到（这是当前 iOS 客户端本身的限制，与签名方式无关）。

## 想省掉每周重签

- 加入 Apple Developer Program（99 美元/年）：可以用 TestFlight，构建一次 90 天有效，最多 1 万名测试者，也不用连电脑。
- 或用 AltStore（Windows 装 AltServer），同一 Wi-Fi 下自动续签，免去手动重装；仍然受 7 天限制，但不用每周插线。
