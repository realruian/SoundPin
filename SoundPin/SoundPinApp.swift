import SwiftUI
import CoreAudio

@main
struct SoundPinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Before anything reads the settings
        SettingsMigration.run()
    }
    
    var body: some Scene {
        // The menu bar item and panel are AppKit (SoundPanelController): a MenuBarExtra window
        // is only as large as its content, which leaves no room for the glass's shadow.
        MenuBarExtra(L10n.appName, systemImage: "speaker.wave.3.fill", isInserted: .constant(false)) {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: SoundPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let audioManager = AudioManager(deviceService: AudioDeviceService(),
            listeningModeService: ListeningModeService(), priorityManager: PriorityManager(),
            batteryService: BluetoothBatteryService())
        panel = SoundPanelController(audioManager: audioManager)
    }
}

/// Versions up to 2.1 were called Audio Priority Bar and kept their settings under another
/// identifier (1.x under yet another). The first launch under the new name copies them over once.
enum SettingsMigration {
    /// Newest first: the settings of the first one found are taken
    private static let oldDomains = ["app.audioprioritybar", "com.example.AudioPriorityBar"]
    private static let doneKey = "migratedFromAudioPriorityBar"
    /// The app's own settings. The old file also holds what the system kept there for the
    /// old app, such as the place of its menu bar icon, which is not carried over.
    private static let keys = [
        "inputPriorities", "speakerPriorities", "headphonePriorities", "deviceCategories",
        "currentMode", "customMode", "neverUseDevices",
        "hiddenMics", "hiddenSpeakers", "hiddenHeadphones", "knownDevices", "appLanguage",
    ]

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        if let old = oldDomains.lazy.compactMap({ defaults.persistentDomain(forName: $0) }).first {
            for key in keys where defaults.object(forKey: key) == nil {
                if let value = old[key] {
                    defaults.set(value, forKey: key)
                }
            }
        }
        defaults.set(true, forKey: doneKey)
    }
}
