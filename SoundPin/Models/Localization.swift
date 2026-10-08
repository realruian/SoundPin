import Foundation

/// The interface language: the system's, or a fixed choice made in the menu
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case chinese = "zh-Hans"

    var id: String { rawValue }
}

/// The text of the interface, in English and Simplified Chinese
enum L10n {
    private static let settingKey = "appLanguage"

    static var setting: AppLanguage = AppLanguage(rawValue: UserDefaults.standard.string(forKey: settingKey) ?? "") ?? .system {
        didSet {
            UserDefaults.standard.set(setting.rawValue, forKey: settingKey)
        }
    }

    static var isChinese: Bool {
        switch setting {
        case .english: return false
        case .chinese: return true
        case .system: return Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        }
    }

    private static func pick(_ english: String, _ chinese: String) -> String {
        isChinese ? chinese : english
    }

    // Panel
    static var sound: String { pick("Sound", "声音") }
    static var headphones: String { pick("Headphones", "耳机") }
    static var speakers: String { pick("Speakers", "扬声器") }
    static var microphones: String { pick("Microphones", "麦克风") }
    static var soundSettings: String { pick("Sound Settings…", "声音设置…") }
    static var noDevices: String { pick("No Devices", "没有设备") }
    static var done: String { pick("Done", "完成") }
    static var autoSwitchPaused: String { pick("Auto-Switch Paused", "自动切换已暂停") }
    static var resumeAutoSwitchHelp: String { pick("Click to resume automatic switching", "点击恢复自动切换") }

    static func ignoredCount(_ count: Int) -> String {
        pick("\(count) Ignored", "已忽略 \(count) 个")
    }

    // Main menu
    static var autoSwitch: String { pick("Switch Devices Automatically", "自动切换设备") }
    static var openAtLogin: String { pick("Open at Login", "开机启动") }
    static var editDeviceList: String { pick("Edit Device List", "编辑设备列表") }
    static var language: String { pick("Language", "语言") }
    static var systemDefault: String { pick("System Default", "跟随系统") }
    static var quit: String { pick("Quit SoundPin", "退出定音") }

    // Device menu
    static var muted: String { pick("Muted", "已静音") }
    static var moveToSpeakers: String { pick("Move to Speakers", "移到扬声器") }
    static var moveToHeadphones: String { pick("Move to Headphones", "移到耳机") }
    static var stopIgnoring: String { pick("Stop Ignoring", "取消忽略") }
    static var ignoreEntirely: String { pick("Ignore Entirely", "完全忽略") }
    static var forgetDevice: String { pick("Forget Device", "忘记此设备") }
    static var allowAutoSelect: String { pick("Allow Automatic Selection", "恢复自动选用") }
    static var neverAutoSelect: String { pick("Never Select Automatically", "永不自动选用") }

    static func ignore(in type: AudioDeviceType, category: OutputCategory?) -> String {
        if type == .input {
            return pick("Ignore as Microphone", "在麦克风列表中忽略")
        }
        return category == .headphone
            ? pick("Ignore as Headphones", "在耳机列表中忽略")
            : pick("Ignore as Speaker", "在扬声器列表中忽略")
    }

    // How long ago a disconnected device was last seen
    static var justNow: String { pick("now", "刚刚") }
    static func minutesAgo(_ n: Int) -> String { pick("\(n)m ago", "\(n) 分钟前") }
    static func hoursAgo(_ n: Int) -> String { pick("\(n)h ago", "\(n) 小时前") }
    static func daysAgo(_ n: Int) -> String { pick("\(n)d ago", "\(n) 天前") }
    static func weeksAgo(_ n: Int) -> String { pick("\(n)w ago", "\(n) 周前") }
    static func monthsAgo(_ n: Int) -> String { pick("\(n)mo ago", "\(n) 个月前") }
}
