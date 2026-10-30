# 狮山见 iOS 客户端

SwiftUI 原生实现，目录结构、页面、交互和 Android 客户端一一对应：

```
Data/                 模型、请求、网络、登录态、格式化、场景
UI/Theme/             颜色与主题
UI/Components/        卡片、头像、按钮、FlowLayout、举报、游客门禁
UI/Auth/              登录、注册、人机验证、资料引导
UI/Hall/              大厅
UI/Card/              卡片详情
UI/Create/            发卡
UI/Chat/              消息列表、私聊
UI/Me/                我的、我的卡片、我的意向、设置、设备、注销
UI/AppRoot.swift      路由与四个 tab
```

## 环境

- macOS 13 或更高
- Xcode 16 或更高（项目使用 Xcode 16 的同步文件夹工程格式）
- iOS 17+ 模拟器或 iPhone

只跑模拟器不需要 Apple Developer 账号。真机调试需要 Apple ID（免费账号签名 7 天有效）；TestFlight / App Store 需要 Apple Developer Program（99 美元/年）。

## 打开与运行

1. 用 Xcode 打开 `Shishanjian.xcodeproj`。
2. 选中 `Shishanjian` target → Signing & Capabilities，选择自己的 Team。
3. 选择 iPhone 模拟器，运行。

如果当前 Xcode 打不开同步文件夹工程，可以安装 XcodeGen 后重新生成：

```bash
brew install xcodegen
cd ios
xcodegen generate
open Shishanjian.xcodeproj
```

## 后端地址

默认写在 `Config/Info.plist` 的 `API_BASE_URL`：

```
http://127.0.0.1:8080/
```

生产后端：`https://zymusic.top/shishanjian/`。

iOS 模拟器可以直接访问 Mac 的 localhost。真机调试时改成 Mac 的局域网 IP，例如 `http://192.168.1.10:8080/`，并保证后端监听 `0.0.0.0`、手机和 Mac 在同一网络。开发环境已在 Info.plist 中允许明文 HTTP；上线需要换 HTTPS。

## 已实现

- 游客浏览大厅、卡片详情和公开评论；发卡、评论、意向、聊天、我的需要登录
- 登录、两步注册（邮箱前缀 + 滑块人机验证 + 邮箱验证码）、资料引导
- 大厅场景筛选自动换行、搜索、分页
- 卡片详情、评论区树、回复、删除、评论区模式、举报
- 发卡：仅场景和标题必填，其余选填；预设标签最多 3 个
- 我的卡片（隐藏 / 重新公开 / 结束 / 随时删除）、收到的意向、我的意向
- 消息列表、私聊轮询、文字/图片、已读、撤回、拉黑
- 我的资料/头像、登录设备、退出、注销
- Token 自动续期：读取 `X-Renewed-Token` 并静默替换

## 当前状态

工程代码写在 Windows 上，当前机器没有 macOS/Xcode，因此尚未编译、签名和在模拟器/真机上运行验证。需要一台 Mac 做首次编译和真机截图验证。
