import Foundation

struct SceneMeta: Identifiable, Hashable {
    let key: String
    let label: String
    let color: UInt32
    let light: UInt32
    let symbol: String

    var id: String { key }
}

let appScenes: [SceneMeta] = [
    SceneMeta(key: "study", label: "自习", color: 0x3E6FB0, light: 0xEDF2FA, symbol: "book"),
    SceneMeta(key: "sport", label: "运动", color: 0x3E8E4A, light: 0xEDF7EE, symbol: "basketball"),
    SceneMeta(key: "meal", label: "饭搭子", color: 0xD97706, light: 0xFDF2E4, symbol: "fork.knife"),
    SceneMeta(key: "car", label: "拼车", color: 0x0F766E, light: 0xE8F5F3, symbol: "car"),
    SceneMeta(key: "interest", label: "兴趣", color: 0x8B5E3C, light: 0xF6EEE8, symbol: "star"),
    SceneMeta(key: "help", label: "互助", color: 0x6B7A8F, light: 0xEFF2F6, symbol: "hand.raised"),
    SceneMeta(key: "errand", label: "跑腿", color: 0xC28B00, light: 0xFBF4DF, symbol: "bag"),
    SceneMeta(key: "friend", label: "找朋友", color: 0xB25C5C, light: 0xF9EDED, symbol: "person.2"),
    SceneMeta(key: "other", label: "其他", color: 0x7A6C5C, light: 0xF3EFE9, symbol: "ellipsis"),
]

func sceneMeta(_ key: String?) -> SceneMeta {
    appScenes.first { $0.key == key } ?? appScenes.last!
}

let appTagOptions = ["考研", "安静", "早起", "新手友好", "认真", "长期", "有车", "拼单", "求带", "闲聊"]
