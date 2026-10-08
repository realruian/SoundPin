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
                .accessibilityLabel(L10n.appName)
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
    /// False while the output in use has no volume the Mac can set
    @Published var hasVolumeControl: Bool = true
    @Published var isEditMode: Bool = false
    @Published var isCustomMode: Bool = false
    /// Row identities, not device ids: a device with a microphone and a speaker has one id for the two
    @Published var mutedRowIDs: Set<String> = []
    @Published var isActiveOutputMuted: Bool = false
    /// Published so that every view redraws its text when the language changes
    @Published var language: AppLanguage = L10n.setting {
        didSet { L10n.setting = language }
    }

    private let deviceService = AudioDeviceService()
    let priorityManager = PriorityManager()
    private var connectedDeviceUIDs: Set<String> = []

    /// Symbol for the menu bar, following what the system Sound icon shows:
    /// the headphones in use, a slashed speaker when muted, otherwise waves by volume
    /// (all of them for an output whose volume cannot be read)
    var menuBarSymbol: (name: String, value: Double?) {
        if let headphone = headphoneDevices.first(where: { $0.isConnected && $0.id == currentOutputId }) {
            return (DeviceGlyph.symbol(for: headphone, category: .headphone), nil)
        }
        if isActiveOutputMuted {
            return ("speaker.slash.fill", nil)
        }
        return ("speaker.wave.3.fill", hasVolumeControl ? Double(volume) : nil)
    }

    func refreshVolume() {
        hasVolumeControl = deviceService.canSetOutputVolume()
        volume = deviceService.getOutputVolume()
    }

    func refreshMuteStatus() {
        var muted: Set<String> = []
        for device in inputDevices + speakerDevices + headphoneDevices where device.isConnected {
            if deviceService.isDeviceMuted(device.id, type: device.type) {
                muted.insert(device.rowID)
            }
        }
        mutedRowIDs = muted
        let activeOutput = (speakerDevices + headphoneDevices).first { $0.isConnected && $0.id == currentOutputId }
        isActiveOutputMuted = activeOutput.map { muted.contains($0.rowID) } ?? false
    }

    func isDeviceMuted(_ device: AudioDevice) -> Bool {
        mutedRowIDs.contains(device.rowID)
    }

    func setVolume(_ newVolume: Float) {
        guard hasVolumeControl else { return }
        volume = newVolume
        deviceService.setOutputVolume(newVolume)
        // Like the system's slider: turning a muted output up unmutes it
        if newVolume > 0 {
            deviceService.unmuteOutput()
        }
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
            followOutputInUseAtLaunch()
            autoSwitchModeIfNeeded(newlyConnectedUIDs: [])
            applyHighestPriorityInput()
            applyHighestPriorityOutput()
        }
    }

    /// The mode stored at the last quit can be out of date: headphones may have been put on
    /// or taken off since. At launch, the list that holds the output in use is the one in
    /// use. An output that is in neither list, or marked "never select automatically",
    /// decides nothing, and the stored mode stands.
    private func followOutputInUseAtLaunch() {
        func holdsOutputInUse(_ list: [AudioDevice]) -> Bool {
            list.contains { $0.isConnected && $0.id == currentOutputId && !priorityManager.isNeverUse($0) }
        }
        if holdsOutputInUse(headphoneDevices) {
            switchMode(to: .headphone)
        } else if holdsOutputInUse(speakerDevices) {
            switchMode(to: .speaker)
        }
    }

    /// Changes the list in use and stores it, without picking a device
    private func switchMode(to mode: OutputCategory) {
        guard currentMode != mode else { return }
        currentMode = mode
        priorityManager.currentMode = mode
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
        let inputInUse = deviceService.getCurrentDefaultDevice(type: .input)
        let outputInUse = deviceService.getCurrentDefaultDevice(type: .output)

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
            priorityManager.seedPriorities(allInputs, inUse: inputInUse, type: .input)
            inputDevices = priorityManager.sortByPriority(allInputs, type: .input)
            hiddenInputDevices = []
            let speakers = allOutputs.filter { priorityManager.getCategory(for: $0) == .speaker }
            let headphones = allOutputs.filter { priorityManager.getCategory(for: $0) == .headphone }
            priorityManager.seedPriorities(speakers, inUse: outputInUse, category: .speaker)
            priorityManager.seedPriorities(headphones, inUse: outputInUse, category: .headphone)
            speakerDevices = priorityManager.sortByPriority(speakers, category: .speaker)
            headphoneDevices = priorityManager.sortByPriority(headphones, category: .headphone)
            hiddenSpeakerDevices = []
            hiddenHeadphoneDevices = []
        } else {
            // Ignored devices are left out of the lists. A device marked "never select
            // automatically" stays in them: it is skipped when the app picks a device,
            // and can still be picked by hand.
            let visibleInputs = connectedInputs.filter { !priorityManager.isHidden($0) }
            priorityManager.seedPriorities(visibleInputs, inUse: inputInUse, type: .input)
            inputDevices = priorityManager.sortByPriority(visibleInputs, type: .input)
            hiddenInputDevices = connectedInputs.filter { priorityManager.isHidden($0) }

            let speakers = connectedOutputs.filter { priorityManager.getCategory(for: $0) == .speaker }
            let headphones = connectedOutputs.filter { priorityManager.getCategory(for: $0) == .headphone }
            let visibleSpeakers = speakers.filter { !priorityManager.isHidden($0, inCategory: .speaker) }
            let visibleHeadphones = headphones.filter { !priorityManager.isHidden($0, inCategory: .headphone) }
            priorityManager.seedPriorities(visibleSpeakers, inUse: outputInUse, category: .speaker)
            priorityManager.seedPriorities(visibleHeadphones, inUse: outputInUse, category: .headphone)
            speakerDevices = priorityManager.sortByPriority(visibleSpeakers, category: .speaker)
            headphoneDevices = priorityManager.sortByPriority(visibleHeadphones, category: .headphone)
            hiddenSpeakerDevices = speakers.filter { priorityManager.isHidden($0, inCategory: .speaker) }
            hiddenHeadphoneDevices = headphones.filter { priorityManager.isHidden($0, inCategory: .headphone) }
        }
        currentInputId = inputInUse
        currentOutputId = outputInUse
    }

    func toggleEditMode() {
        isEditMode.toggle()
        refreshDevices()
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

    func setCustomMode(_ enabled: Bool) {
        handPickedUIDs = [:]
        isCustomMode = enabled
        priorityManager.isCustomMode = enabled
        if !enabled {
            applyHighestPriorityInput()
            applyHighestPriorityOutput()
        }
    }

    func setCategory(_ category: OutputCategory, for device: AudioDevice) {
        let previous = priorityManager.getCategory(for: device)
        let wasInUse = device.isConnected && device.id == currentOutputId
        priorityManager.setCategory(category, for: device)
        refreshDevices()
        guard !isCustomMode else { return }
        if category != previous {
            followCategoryChange(of: device, to: category, wasInUse: wasInUse)
        }
        autoSwitchModeIfNeeded(newlyConnectedUIDs: [])
        applyHighestPriorityOutput()
    }

    /// A connected device that changes lists takes the mode with it, so that telling the
    /// app "these are headphones" does not send the sound to a speaker.
    private func followCategoryChange(of device: AudioDevice, to category: OutputCategory, wasInUse: Bool) {
        let list = category == .headphone ? headphoneDevices : speakerDevices
        guard let index = list.firstIndex(where: { $0.uid == device.uid && $0.isConnected }) else { return }
        if wasInUse {
            // The device in use stays in use: its new list becomes the one in use, with it on top
            switchMode(to: category)
            if index > 0 {
                if category == .headphone {
                    moveHeadphoneDevice(from: IndexSet(integer: index), to: 0)
                } else {
                    moveSpeakerDevice(from: IndexSet(integer: index), to: 0)
                }
            }
        } else if category == .headphone, !priorityManager.isNeverUse(list[index]) {
            // The same as headphones that have just been connected
            handPickedUIDs[.output] = nil
            switchMode(to: .headphone)
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
        guard let moved = devices(at: source, movingTo: destination, in: inputDevices) else { return }
        inputDevices.move(fromOffsets: source, toOffset: destination)
        priorityManager.savePriorities(inputDevices, moved: moved, type: .input)
        // Switch to top input if it's connected
        if let topInput = deviceToUseAfterMove(in: inputDevices, type: .input) {
            applyInputDevice(topInput)
        }
    }

    func moveSpeakerDevice(from source: IndexSet, to destination: Int) {
        guard let moved = devices(at: source, movingTo: destination, in: speakerDevices) else { return }
        speakerDevices.move(fromOffsets: source, toOffset: destination)
        priorityManager.savePriorities(speakerDevices, moved: moved, category: .speaker)
        // Switch to top speaker only if we're in speaker mode and top speaker is connected
        if currentMode == .speaker, let topSpeaker = deviceToUseAfterMove(in: speakerDevices, type: .output) {
            applyOutputDevice(topSpeaker)
        }
    }

    func moveHeadphoneDevice(from source: IndexSet, to destination: Int) {
        guard let moved = devices(at: source, movingTo: destination, in: headphoneDevices) else { return }
        headphoneDevices.move(fromOffsets: source, toOffset: destination)
        priorityManager.savePriorities(headphoneDevices, moved: moved, category: .headphone)
        // Switch to top headphone if it's connected
        if let topHeadphone = deviceToUseAfterMove(in: headphoneDevices, type: .output) {
            applyOutputDevice(topHeadphone)
        }
    }

    /// The devices about to move, or nil when the list changed under a drag and the places no longer exist
    private func devices(at source: IndexSet, movingTo destination: Int, in list: [AudioDevice]) -> [AudioDevice]? {
        guard source.allSatisfy(list.indices.contains), (0...list.count).contains(destination) else { return nil }
        return source.map { list[$0] }
    }

    /// Reordering puts the top of the list to use if it is connected. Devices marked "never
    /// select automatically" are passed over, and a device picked by hand stays in use.
    private func deviceToUseAfterMove(in list: [AudioDevice], type: AudioDeviceType) -> AudioDevice? {
        guard !isKeepingHandPick(type),
              let top = list.first(where: { !priorityManager.isNeverUse($0) }), top.isConnected else {
            return nil
        }
        return top
    }

    func setInputDevice(_ device: AudioDevice) {
        handPickedUIDs[.input] = priorityManager.isNeverUse(device) ? device.uid : nil
        applyInputDevice(device)
    }

    func setOutputDevice(_ device: AudioDevice) {
        handPickedUIDs[.output] = priorityManager.isNeverUse(device) ? device.uid : nil
        applyOutputDevice(device)
    }

    /// A device marked "never select automatically" that the user picked by hand, per side.
    /// The app leaves it in use, instead of going back to the top of the list at the next
    /// device event, until the user picks another device, it stops being the device in
    /// use, it is disconnected, or headphones are connected. Not stored: after a restart
    /// the app picks by priority again.
    private var handPickedUIDs: [AudioDeviceType: String] = [:]

    private func isKeepingHandPick(_ type: AudioDeviceType) -> Bool {
        guard let uid = handPickedUIDs[type] else { return false }
        let listed = type == .input ? inputDevices : speakerDevices + headphoneDevices
        let currentId = type == .input ? currentInputId : currentOutputId
        if let device = listed.first(where: { $0.uid == uid && $0.isConnected }),
           device.id == currentId, priorityManager.isNeverUse(device) {
            return true
        }
        handPickedUIDs[type] = nil
        return false
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
        // The slider shows the volume of the output in use
        refreshVolume()
    }

    private func applyHighestPriorityInput() {
        guard !isKeepingHandPick(.input) else { return }
        if let first = inputDevices.first(where: { $0.isConnected && !priorityManager.isNeverUse($0) }) {
            applyInputDevice(first)
        }
    }

    private func applyHighestPriorityOutput() {
        let devices = activeOutputDevices
        if !isKeepingHandPick(.output),
           let first = devices.first(where: { $0.isConnected && !priorityManager.isNeverUse($0) }) {
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
        refreshVolume()
        
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
        // Devices marked "never select automatically" do not count: connecting one changes nothing
        let connectedHeadphones = headphoneDevices.filter { $0.isConnected && !priorityManager.isNeverUse($0) }
        let hasConnectedHeadphones = !connectedHeadphones.isEmpty
        let hasConnectedSpeakers = speakerDevices.contains { $0.isConnected && !priorityManager.isNeverUse($0) }
        
        // Check if a new headphone just connected
        let newHeadphoneConnected = connectedHeadphones.contains { newlyConnectedUIDs.contains($0.uid) }
        
        if newHeadphoneConnected {
            // Headphones that have just been connected win over a device picked by hand
            handPickedUIDs[.output] = nil
        }

        if newHeadphoneConnected && currentMode != .headphone {
            // A new headphone just connected - switch to headphone mode
            currentMode = .headphone
            priorityManager.currentMode = .headphone
        } else if !hasConnectedHeadphones && hasConnectedSpeakers && currentMode == .headphone && !isKeepingHandPick(.output) {
            // All headphones disconnected - switch back to speaker mode
            currentMode = .speaker
            priorityManager.currentMode = .speaker
        }
    }
}
