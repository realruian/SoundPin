import SwiftUI
import CoreAudio

@main
struct SoundPinApp: App {
    @StateObject private var audioManager = AudioManager()

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
        }
        .menuBarExtraStyle(.window)
    }
}

/// Versions up to 2.1 were called Audio Priority Bar and kept their settings under another
/// identifier. The first launch under the new name copies them over once.
enum SettingsMigration {
    private static let oldDomain = "app.audioprioritybar"
    private static let doneKey = "migratedFromAudioPriorityBar"

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        if let old = defaults.persistentDomain(forName: oldDomain) {
            for (key, value) in old where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: doneKey)
    }
}

@MainActor
class AudioManager: ObservableObject {
    @Published var inputDevices: [AudioDevice] = []
    @Published var speakerDevices: [AudioDevice] = []
    @Published var headphoneDevices: [AudioDevice] = []
    @Published var hiddenInputDevices: [AudioDevice] = []
    @Published var hiddenSpeakerDevices: [AudioDevice] = []
    @Published var hiddenHeadphoneDevices: [AudioDevice] = []
    @Published var currentInputId: AudioObjectID?
    @Published var currentOutputId: AudioObjectID?
    @Published var currentMode: OutputCategory = .speaker
    @Published var volume: Float = 0
    @Published var isEditMode: Bool = false
    @Published var isCustomMode: Bool = false
    @Published var mutedDeviceIds: Set<AudioObjectID> = []
    @Published var isActiveOutputMuted: Bool = false
    @Published var isActiveInputMuted: Bool = false
    /// Published so that every view redraws its text when the language changes
    @Published var language: AppLanguage = L10n.setting {
        didSet { L10n.setting = language }
    }

    private let deviceService = AudioDeviceService()
    let priorityManager = PriorityManager()
    private var connectedDeviceUIDs: Set<String> = []

    /// Symbol for the menu bar, following what the system Sound icon shows:
    /// the headphones in use, a slashed speaker when muted, otherwise waves by volume
    var menuBarSymbol: (name: String, value: Double?) {
        if let headphone = headphoneDevices.first(where: { $0.isConnected && $0.id == currentOutputId }) {
            return (DeviceGlyph.symbol(for: headphone, category: .headphone), nil)
        }
        if isActiveOutputMuted {
            return ("speaker.slash.fill", nil)
        }
        return ("speaker.wave.3.fill", Double(volume))
    }

    func refreshVolume() {
        volume = deviceService.getOutputVolume()
    }

    func refreshMuteStatus() {
        var muted: Set<AudioObjectID> = []
        for device in inputDevices where device.isConnected {
            if deviceService.isDeviceMuted(device.id, type: .input) {
                muted.insert(device.id)
            }
        }
        for device in speakerDevices where device.isConnected {
            if deviceService.isDeviceMuted(device.id, type: .output) {
                muted.insert(device.id)
            }
        }
        for device in headphoneDevices where device.isConnected {
            if deviceService.isDeviceMuted(device.id, type: .output) {
                muted.insert(device.id)
            }
        }
        mutedDeviceIds = muted
        if let outputId = currentOutputId {
            isActiveOutputMuted = muted.contains(outputId)
        } else {
            isActiveOutputMuted = false
        }
        if let inputId = currentInputId {
            isActiveInputMuted = muted.contains(inputId)
        } else {
            isActiveInputMuted = false
        }
    }

    func isDeviceMuted(_ device: AudioDevice) -> Bool {
        mutedDeviceIds.contains(device.id)
    }

    func setVolume(_ newVolume: Float) {
        volume = newVolume
        deviceService.setOutputVolume(newVolume)
    }

    var activeOutputDevices: [AudioDevice] {
        switch currentMode {
        case .speaker: return speakerDevices
        case .headphone: return headphoneDevices
        }
    }

    init() {
        currentMode = priorityManager.currentMode
        isCustomMode = priorityManager.isCustomMode
        refreshDevices()
        previousConnectedUIDs = connectedDeviceUIDs  // Initialize tracking
        refreshVolume()
        refreshMuteStatus()
        setupDeviceChangeListener()
        setupMuteVolumeListener()
        if !isCustomMode {
            applyHighestPriorityInput()
            applyHighestPriorityOutput()
        }
    }

    private func setupMuteVolumeListener() {
        deviceService.onMuteOrVolumeChanged = { [weak self] in
            Task { @MainActor in
                self?.handleMuteOrVolumeChange()
            }
        }
    }

    private func handleMuteOrVolumeChange() {
        refreshMuteStatus()
        refreshVolume()
    }

    func refreshDevices() {
        let allConnectedDevices = deviceService.getDevices()
        connectedDeviceUIDs = Set(allConnectedDevices.map { $0.uid })
        priorityManager.rememberDevices(allConnectedDevices)
        let connectedInputs = allConnectedDevices.filter { $0.type == .input }
        let connectedOutputs = allConnectedDevices.filter { $0.type == .output }

        if isEditMode {
            let knownDevices = priorityManager.getKnownDevices()
            var allInputs: [AudioDevice] = connectedInputs
            for stored in knownDevices where stored.isInput {
                if !connectedDeviceUIDs.contains(stored.uid) {
                    allInputs.append(.disconnected(uid: stored.uid, name: stored.name, type: .input))
                }
            }
            var allOutputs: [AudioDevice] = connectedOutputs
            for stored in knownDevices where !stored.isInput {
                if !connectedDeviceUIDs.contains(stored.uid) {
                    allOutputs.append(.disconnected(uid: stored.uid, name: stored.name, type: .output))
                }
            }
            inputDevices = priorityManager.sortByPriority(allInputs, type: .input)
            hiddenInputDevices = []
            let speakers = allOutputs.filter { priorityManager.getCategory(for: $0) == .speaker }
            let headphones = allOutputs.filter { priorityManager.getCategory(for: $0) == .headphone }
            speakerDevices = priorityManager.sortByPriority(speakers, category: .speaker)
            headphoneDevices = priorityManager.sortByPriority(headphones, category: .headphone)
            hiddenSpeakerDevices = []
            hiddenHeadphoneDevices = []
        } else {
            // Filter out hidden and never-use devices in normal mode
            let visibleInputs = connectedInputs.filter { !priorityManager.isHidden($0) && !priorityManager.isNeverUse($0) }
            // Hidden inputs: regular hidden first, then never-use
            let regularHiddenInputs = connectedInputs.filter { priorityManager.isHidden($0) && !priorityManager.isNeverUse($0) }
            let neverUseInputs = connectedInputs.filter { priorityManager.isNeverUse($0) }
            inputDevices = priorityManager.sortByPriority(visibleInputs, type: .input)
            hiddenInputDevices = regularHiddenInputs + neverUseInputs

            let speakers = connectedOutputs.filter { priorityManager.getCategory(for: $0) == .speaker }
            let headphones = connectedOutputs.filter { priorityManager.getCategory(for: $0) == .headphone }
            let visibleSpeakers = speakers.filter { !priorityManager.isHidden($0, inCategory: .speaker) && !priorityManager.isNeverUse($0) }
            let visibleHeadphones = headphones.filter { !priorityManager.isHidden($0, inCategory: .headphone) && !priorityManager.isNeverUse($0) }
            // Hidden outputs: regular hidden first, then never-use
            let regularHiddenSpeakers = speakers.filter { priorityManager.isHidden($0, inCategory: .speaker) && !priorityManager.isNeverUse($0) }
            let neverUseSpeakers = speakers.filter { priorityManager.isNeverUse($0) }
            let regularHiddenHeadphones = headphones.filter { priorityManager.isHidden($0, inCategory: .headphone) && !priorityManager.isNeverUse($0) }
            let neverUseHeadphones = headphones.filter { priorityManager.isNeverUse($0) }
            speakerDevices = priorityManager.sortByPriority(visibleSpeakers, category: .speaker)
            headphoneDevices = priorityManager.sortByPriority(visibleHeadphones, category: .headphone)
            hiddenSpeakerDevices = regularHiddenSpeakers + neverUseSpeakers
            hiddenHeadphoneDevices = regularHiddenHeadphones + neverUseHeadphones
        }
        currentInputId = deviceService.getCurrentDefaultDevice(type: .input)
        currentOutputId = deviceService.getCurrentDefaultDevice(type: .output)
    }

    func toggleEditMode() {
        isEditMode.toggle()
        refreshDevices()
    }

    func isDeviceConnected(_ device: AudioDevice) -> Bool {
        connectedDeviceUIDs.contains(device.uid)
    }

    /// Tracks device UIDs from the previous refresh to detect new connections
    private var previousConnectedUIDs: Set<String> = []
    
    func setMode(_ mode: OutputCategory) {
        currentMode = mode
        priorityManager.currentMode = mode
        if !isCustomMode {
            applyHighestPriorityOutput()
        }
    }

    func toggleMode() {
        let newMode: OutputCategory = currentMode == .speaker ? .headphone : .speaker
        setMode(newMode)
    }

    func setCustomMode(_ enabled: Bool) {
        isCustomMode = enabled
        priorityManager.isCustomMode = enabled
        if !enabled {
            applyHighestPriorityInput()
            applyHighestPriorityOutput()
        }
    }

    func setCategory(_ category: OutputCategory, for device: AudioDevice) {
        priorityManager.setCategory(category, for: device)
        refreshDevices()
        if !isCustomMode {
            applyHighestPriorityOutput()
        }
    }

    func hideDevice(_ device: AudioDevice, category: OutputCategory? = nil) {
        if device.type == .input {
            priorityManager.hideDevice(device)
        } else if let cat = category {
            priorityManager.hideDevice(device, inCategory: cat)
        } else {
            priorityManager.hideDevice(device)
        }
        refreshDevices()
        if !isCustomMode {
            if device.type == .input {
                applyHighestPriorityInput()
            } else {
                applyHighestPriorityOutput()
            }
        }
    }

    func hideDeviceEntirely(_ device: AudioDevice) {
        priorityManager.hideDevice(device, inCategory: .speaker)
        priorityManager.hideDevice(device, inCategory: .headphone)
        refreshDevices()
        if !isCustomMode {
            applyHighestPriorityOutput()
        }
    }

    func unhideDevice(_ device: AudioDevice, category: OutputCategory? = nil) {
        if device.type == .input {
            priorityManager.unhideDevice(device)
        } else if let cat = category {
            priorityManager.unhideDevice(device, fromCategory: cat)
        } else {
            priorityManager.unhideDevice(device)
        }
        refreshDevices()
    }

    func isDeviceIgnored(_ device: AudioDevice, inCategory category: OutputCategory? = nil) -> Bool {
        if device.type == .input {
            return priorityManager.isHidden(device)
        } else if let cat = category {
            return priorityManager.isHidden(device, inCategory: cat)
        } else {
            return priorityManager.isHidden(device)
        }
    }

    func isNeverUse(_ device: AudioDevice) -> Bool {
        priorityManager.isNeverUse(device)
    }

    func setNeverUse(_ device: AudioDevice, neverUse: Bool) {
        priorityManager.setNeverUse(device, neverUse: neverUse)
        refreshDevices()
        if !isCustomMode {
            if device.type == .input {
                applyHighestPriorityInput()
            } else {
                applyHighestPriorityOutput()
            }
        }
    }

    func moveInputDevice(from source: IndexSet, to destination: Int) {
        inputDevices.move(fromOffsets: source, toOffset: destination)
        priorityManager.savePriorities(inputDevices, type: .input)
        // Switch to top input if it's connected
        if let topInput = inputDevices.first, topInput.isConnected {
            applyInputDevice(topInput)
        }
    }

    func moveSpeakerDevice(from source: IndexSet, to destination: Int) {
        speakerDevices.move(fromOffsets: source, toOffset: destination)
        priorityManager.savePriorities(speakerDevices, category: .speaker)
        // Switch to top speaker only if we're in speaker mode and top speaker is connected
        if currentMode == .speaker, let topSpeaker = speakerDevices.first, topSpeaker.isConnected {
            applyOutputDevice(topSpeaker)
        }
    }

    func moveHeadphoneDevice(from source: IndexSet, to destination: Int) {
        headphoneDevices.move(fromOffsets: source, toOffset: destination)
        priorityManager.savePriorities(headphoneDevices, category: .headphone)
        // Switch to top headphone if it's connected
        if let topHeadphone = headphoneDevices.first, topHeadphone.isConnected {
            applyOutputDevice(topHeadphone)
        }
    }

    func setInputDevice(_ device: AudioDevice) {
        applyInputDevice(device)
    }

    func setOutputDevice(_ device: AudioDevice) {
        applyOutputDevice(device)
    }

    // A device that is already the default is left alone
    private func applyInputDevice(_ device: AudioDevice) {
        if deviceService.getCurrentDefaultDevice(type: .input) != device.id {
            deviceService.setDefaultDevice(device.id, type: .input)
        }
        currentInputId = device.id
    }

    private func applyOutputDevice(_ device: AudioDevice) {
        if deviceService.getCurrentDefaultDevice(type: .output) != device.id {
            deviceService.setDefaultDevice(device.id, type: .output)
        }
        currentOutputId = device.id
    }

    private func applyHighestPriorityInput() {
        if let first = inputDevices.first(where: { $0.isConnected && !priorityManager.isNeverUse($0) }) {
            applyInputDevice(first)
        }
    }

    private func applyHighestPriorityOutput() {
        let devices = activeOutputDevices
        if let first = devices.first(where: { $0.isConnected && !priorityManager.isNeverUse($0) }) {
            applyOutputDevice(first)
        }
        refreshMuteStatus()
    }

    private func setupDeviceChangeListener() {
        deviceService.onDevicesChanged = { [weak self] in
            Task { @MainActor in
                self?.handleDeviceChange()
            }
        }
        deviceService.startListening()
    }

    private func handleDeviceChange() {
        let oldConnectedUIDs = previousConnectedUIDs
        refreshDevices()
        refreshMuteStatus()
        
        // Detect newly connected devices
        let newlyConnectedUIDs = connectedDeviceUIDs.subtracting(oldConnectedUIDs)
        previousConnectedUIDs = connectedDeviceUIDs
        
        if !isCustomMode {
            // Auto-switch mode only when a new headphone connects or all headphones disconnect
            autoSwitchModeIfNeeded(newlyConnectedUIDs: newlyConnectedUIDs)
            applyHighestPriorityInput()
            applyHighestPriorityOutput()
        }
    }
    
    /// Automatically switches between headphone and speaker mode based on device connections.
    /// Only triggers on:
    /// 1. A new headphone device connects → switch to headphone mode
    /// 2. All headphones disconnect → switch to speaker mode
    private func autoSwitchModeIfNeeded(newlyConnectedUIDs: Set<String>) {
        let connectedHeadphones = headphoneDevices.filter { $0.isConnected }
        let hasConnectedHeadphones = !connectedHeadphones.isEmpty
        let hasConnectedSpeakers = speakerDevices.contains { $0.isConnected }
        
        // Check if a new headphone just connected
        let newHeadphoneConnected = connectedHeadphones.contains { newlyConnectedUIDs.contains($0.uid) }
        
        if newHeadphoneConnected && currentMode != .headphone {
            // A new headphone just connected - switch to headphone mode
            currentMode = .headphone
            priorityManager.currentMode = .headphone
        } else if !hasConnectedHeadphones && hasConnectedSpeakers && currentMode == .headphone {
            // All headphones disconnected - switch back to speaker mode
            currentMode = .speaker
            priorityManager.currentMode = .speaker
        }
    }
}
