import SwiftUI
import CoreAudio

@main
struct SoundPinApp: App {
    @StateObject private var audioManager = AudioManager(deviceService: AudioDeviceService(),
        listeningModeService: ListeningModeService(), priorityManager: PriorityManager(),
        batteryService: BluetoothBatteryService())

    init() {
        // Before anything reads the settings
        SettingsMigration.run()
    }
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(audioManager)
        } label: {
            // One Image only: a label made of several views did not show up reliably
            Image(systemName: audioManager.menuBarSymbol.name, variableValue: audioManager.menuBarSymbol.value)
                .accessibilityLabel(L10n.appName)
        }
        .menuBarExtraStyle(.window)
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
