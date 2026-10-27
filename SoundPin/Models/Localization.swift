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
    /// Preview/check processes keep language changes in memory.
    static var persistsSetting = true

    static var setting: AppLanguage = AppLanguage(rawValue: UserDefaults.standard.string(forKey: settingKey) ?? "") ?? .system {
        didSet {
            if persistsSetting { UserDefaults.standard.set(setting.rawValue, forKey: settingKey) }
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
    static var listeningMode: String { pick("Listening Mode", "听音模式") }
    static var transparency: String { pick("Transparency", "通透") }
    static var adaptive: String { pick("Adaptive", "自适应") }
    static var noiseCancellation: String { pick("Noise Cancellation", "降噪") }
    static var showListeningModes: String { pick("Show Listening Modes", "展开听音模式") }
    static var hideListeningModes: String { pick("Hide Listening Modes", "收起听音模式") }
    static var listeningModePending: String { pick("Switching…", "切换中…") }
    static var listeningModeTimedOut: String { pick("The system hasn’t reported the requested mode. Try again.", "系统尚未返回所选模式，请重试。") }
    static var listeningModeUnavailable: String { pick("Listening modes are temporarily unavailable. Try again.", "暂时无法读取听音模式，请重试。") }
    static var listeningModeFailed: String { pick("Couldn’t change the listening mode. Check that your AirPods are connected and try again.", "无法切换听音模式。请检查 AirPods 连接后重试。") }
    static var noDevices: String { pick("No Devices", "没有设备") }
    static var noVolumeControl: String { pick("This device has no volume control", "此设备不支持调节音量") }
    static var done: String { pick("Done", "完成") }
    static var retry: String { pick("Retry", "重试") }
    static var deviceReadUnavailable: String { pick("Devices couldn’t be refreshed", "暂时无法刷新设备") }
    static var deviceSwitchFailed: String { pick("Couldn’t switch device", "设备切换未完成") }
    static func deviceSwitchFailure(_ name: String) -> String {
        pick("Couldn’t confirm the switch to \(name). Check its connection and try again.",
             "未能确认已切换到“\(name)”。请检查连接后重试。")
    }
    static var autoSwitchPaused: String { pick("Auto-Switch Paused", "自动切换已暂停") }
    static var resumeAutoSwitchHelp: String { pick("Click to resume automatic switching", "点击恢复自动切换") }
    static var routingConflictPaused: String { pick("Switching on Hold", "切换暂缓") }
    static func routingConflictHelp(input: Bool, output: Bool) -> String {
        let side = input && output ? pick("input and output", "输入和输出")
            : input ? pick("input", "输入") : pick("output", "输出")
        return pick("Repeated \(side) changes detected. Automatic switching is on hold for up to 60 seconds. Click to retry now.",
                    "检测到\(side)设备被反复切换，自动切换暂缓，最长 60 秒。点击可立即重试。")
    }

    // Battery values are the latest report from macOS; the case can update separately.
    static var batteryDevice: String { pick("Battery", "电量") }
    static var batteryLeft: String { pick("Left", "左耳") }
    static var batteryRight: String { pick("Right", "右耳") }
    static var batteryCase: String { pick("Case", "充电盒") }
    static func batteryCaseShort(_ value: Int) -> String { pick("Case \(value)%", "盒 \(value)%") }
    static var batteryReportHelp: String { pick("Last reported by macOS. The lower earbud level is shown; case updates may be delayed.", "macOS 最近报告的电量。两耳不同时显示较低值；充电盒电量更新可能延迟。") }

    // Main menu
    static var autoSwitch: String { pick("Switch Devices Automatically", "自动切换设备") }
    static var openAtLogin: String { pick("Open at Login", "开机启动") }
    static var loginApprovalRequired: String { pick("Allow in System Settings…", "前往系统设置允许启动…") }
    static var loginApprovalMessage: String { pick("Allow SoundPin in System Settings → General → Login Items & Extensions to enable Open at Login.", "请在系统设置 → 通用 → 登录项与扩展中允许定音启动，然后返回查看状态。") }
    static var loginChangeFailed: String { pick("Couldn’t Update Open at Login", "无法更新开机启动设置") }
    static var loginChangeUnconfirmed: String { pick("The system hasn’t confirmed the change. Check Login Items in System Settings and try again.", "系统尚未确认此更改，请检查系统设置中的登录项后重试。") }
    static var openSystemSettings: String { pick("Open System Settings", "打开系统设置") }
    static var editDeviceList: String { pick("Edit Device List", "编辑设备列表") }
    static var ignoredDevices: String { pick("Ignored Devices", "已忽略的设备") }
    static var language: String { pick("Language", "语言") }
    static var systemDefault: String { pick("System Default", "跟随系统") }
    static var quit: String { pick("Quit SoundPin", "退出定音") }

    // What VoiceOver reads for the parts of the panel that are shown as icons only
    static var appName: String { pick("SoundPin", "定音") }
    static var volume: String { pick("Volume", "音量") }
    static var options: String { pick("Options", "选项") }
    static var notConnected: String { pick("Not Connected", "未连接") }
    static var ignored: String { pick("Ignored", "已忽略") }
    static var moveUp: String { pick("Move Up", "上移") }
    static var moveDown: String { pick("Move Down", "下移") }
    static var moveToTop: String { pick("Move to Top", "置顶") }
    static var listSeparator: String { pick(", ", "，") }

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
