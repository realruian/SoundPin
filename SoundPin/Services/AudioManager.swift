import SwiftUI
import CoreAudio

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
    @Published var listeningModes: [String: ListeningModeState] = [:]
    @Published private(set) var listeningModeRequests: [String: ListeningModeRequestState] = [:]
    @Published private(set) var unavailableListeningModeUIDs: Set<String> = []
    private var listeningModeEndpoints: [String: AudioObjectID] = [:]
    private var modeRequests: [String: ModeRequest] = [:]
    private var modeRecovery: ScheduledAudioAction?
    private var modeRecoveryCount = 0
    private let modeRecoveryDelays: [TimeInterval] = [0.3, 1, 3]
    private let modeReadbackDelays: [TimeInterval] = [0.2, 0.5, 1, 2]

    private final class ModeRequest {
        let device: AudioDevice
        let mode: ListeningMode
        var readbacks = 0
        var scheduled: ScheduledAudioAction?
        init(device: AudioDevice, mode: ListeningMode) { self.device = device; self.mode = mode }
    }
    /// Published so that every view redraws its text when the language changes
    @Published var language: AppLanguage = L10n.setting {
        didSet { L10n.setting = language }
    }

    @Published private(set) var batteryLevels: [String: DeviceBattery] = [:]
    private let batteryService: DeviceBatteryProviding?
    private var batteryRefreshInFlight = false
    private var batteryLastAttempt: Date?
    private var batteryReadAt: Date?
    private var batteryGeneration = 0

    func battery(for device: AudioDevice) -> DeviceBattery? {
        guard !isDeviceReadUnavailable, let address = DeviceBattery.address(for: device) else { return nil }
        return batteryLevels[address]
    }

    /// Called only while the panel is visible. One shared query serves input and
    /// output rows, at most once per minute; failures clear previous readings.
    func refreshBatteryLevels(now: Date = Date()) async {
        guard !Task.isCancelled, let batteryService, !isDeviceReadUnavailable else { return }
        let addresses = Set(connectedDevices.compactMap { DeviceBattery.address(for: $0) })
        guard !addresses.isEmpty else { batteryLevels = [:]; return }
        if let readAt = batteryReadAt, now.timeIntervalSince(readAt) > 120 { batteryLevels = [:] }
        guard !batteryRefreshInFlight else { return }
        if let last = batteryLastAttempt, now.timeIntervalSince(last) < 60 { return }
        batteryRefreshInFlight = true
        batteryLastAttempt = now
        let generation = batteryGeneration
        defer { batteryRefreshInFlight = false }
        let result = await batteryService.readBatteries()
        guard generation == batteryGeneration, !isDeviceReadUnavailable else { return }
        batteryLevels = (result ?? [:]).filter { addresses.contains($0.key) }
        batteryReadAt = result == nil ? nil : now
    }

    private let deviceService: AudioDeviceProviding
    private let listeningModeService: ListeningModeProviding
    private let scheduler: AudioScheduling
    let priorityManager: PriorityManager
    private var connectedRowIDs: Set<String> = []
    private var connectedDevices: [AudioDevice] = []
    private var volumeTarget: AudioDevice?
    private var needsOutputReconciliation = true
    @Published private(set) var isDeviceReadUnavailable = false
    @Published private(set) var pendingRouteRows: Set<String> = []
    @Published var routingFailure: RoutingFailure?
    private var inventoryRetry: ScheduledAudioAction?
    private var inventoryRetryCount = 0
    private let retryDelays: [TimeInterval] = [0.3, 1.0]
    private var pendingRoutes: [AudioDeviceType: RouteRequest] = [:]
    private var failedRows: [AudioDeviceType: Set<String>] = [:]

    struct RoutingFailure: Identifiable {
        let id = UUID()
        let device: AudioDevice
        let manual: Bool
        let category: OutputCategory?
    }

    private final class RouteRequest {
        let id = UUID()
        let device: AudioDevice
        let manual: Bool
        let category: OutputCategory?
        let promote: Bool
        var attempts = 0
        var scheduled: ScheduledAudioAction?
        init(device: AudioDevice, manual: Bool, category: OutputCategory?, promote: Bool) {
            self.device = device; self.manual = manual; self.category = category; self.promote = promote
        }
    }

    /// Symbol for the menu bar, following what the system Sound icon shows:
    /// the headphones in use, a slashed speaker when muted, otherwise waves by volume
    /// (all of them for an output whose volume cannot be read)
    var menuBarSymbol: (name: String, value: Double?) {
        if let headphone = connectedDevices.first(where: { $0.type == .output && $0.id == currentOutputId && priorityManager.getCategory(for: $0) == .headphone }) {
            return (DeviceGlyph.symbol(for: headphone, category: .headphone), nil)
        }
        if isActiveOutputMuted {
            return ("speaker.slash.fill", nil)
        }
        return ("speaker.wave.3.fill", hasVolumeControl ? Double(volume) : nil)
    }

    func refreshVolume() {
        guard let state = deviceService.readOutputVolume() else {
            currentOutputId = deviceService.getCurrentDefaultDevice(type: .output)
            hasVolumeControl = false
            volumeTarget = nil
            return
        }
        currentOutputId = state.deviceID
        volumeTarget = connectedDevices.first { $0.type == .output && $0.id == state.deviceID }
        let readable = state.volume.map { $0.isFinite && (0...1).contains($0) } ?? false
        hasVolumeControl = state.isSettable && readable && volumeTarget != nil
        if let actual = state.volume, readable { volume = actual }
    }

    func refreshMuteStatus() {
        currentOutputId = deviceService.getCurrentDefaultDevice(type: .output)
        var muted: Set<String> = []
        for device in connectedDevices {
            if deviceService.isDeviceMuted(device.id, type: device.type) {
                muted.insert(device.rowID)
            }
        }
        mutedRowIDs = muted
        // Visibility is a preference, not the system's active audio state.
        isActiveOutputMuted = currentOutputId.map {
            deviceService.isDeviceMuted($0, type: .output)
        } ?? false
    }

    func isDeviceMuted(_ device: AudioDevice) -> Bool {
        mutedRowIDs.contains(device.rowID)
    }

    @discardableResult
    func setVolume(_ newVolume: Float) -> Bool {
        guard newVolume.isFinite, hasVolumeControl, let target = volumeTarget else { return false }
        let requested = min(1, max(0, newVolume))
        let accepted = deviceService.setOutputVolume(requested, for: target)
        refreshVolume()
        let confirmed = accepted && hasVolumeControl && volumeTarget?.rowID == target.rowID
            && volumeTarget?.id == target.id && abs(volume - requested) < 0.01
        // Unmute only the original endpoint, after a confirmed positive volume write.
        // A route change between these calls must never unmute its replacement.
        let unmuted = confirmed && requested > 0 ? deviceService.unmuteOutput(for: target) : true
        refreshVolume()
        refreshMuteStatus()
        return confirmed && unmuted
    }

    var activeOutputDevices: [AudioDevice] {
        switch currentMode {
        case .speaker: return speakerDevices
        case .headphone: return headphoneDevices
        }
    }

    init(deviceService: AudioDeviceProviding, listeningModeService: ListeningModeProviding,
         priorityManager: PriorityManager, scheduler: AudioScheduling? = nil,
         batteryService: DeviceBatteryProviding? = nil) {
        self.batteryService = batteryService
        self.deviceService = deviceService
        self.listeningModeService = listeningModeService
        self.priorityManager = priorityManager
        self.scheduler = scheduler ?? MainQueueAudioScheduler()
        currentMode = priorityManager.currentMode
        isCustomMode = priorityManager.isCustomMode
        refreshDevices()
        previousConnectedRowIDs = connectedRowIDs  // Initialize tracking
        refreshVolume()
        refreshMuteStatus()
        setupDeviceChangeListener()
        setupMuteVolumeListener()
        listeningModeService.onChange = { [weak self] in
            Task { @MainActor in self?.refreshListeningModes() }
        }
        if !isCustomMode && !isDeviceReadUnavailable {
            followOutputInUse()
            needsOutputReconciliation = false
            pickAgain(.input)
            pickAgain(.output)
        }
    }

    /// The mode on record can be out of date: headphones may have been put on or taken off
    /// while the app was not running, or while automatic switching was paused. When the app
    /// starts picking devices, the list that holds the output in use is the one in use. An
    /// output the app would not pick by itself decides nothing, and the mode on record stands.
    private func followOutputInUse() {
        func holdsOutputInUse(_ list: [AudioDevice], _ category: OutputCategory) -> Bool {
            list.contains { $0.id == currentOutputId && canPickAutomatically($0, in: category) }
        }
        if holdsOutputInUse(headphoneDevices, .headphone) {
            switchMode(to: .headphone)
        } else if holdsOutputInUse(speakerDevices, .speaker) {
            switchMode(to: .speaker)
        }
    }

    /// Whether the app may pick this device by itself: it is connected, not ignored in the
    /// list it is shown in, and not marked "never select automatically". Being listed is
    /// not enough: while the device list is edited, the lists hold ignored devices too.
    private func canPickAutomatically(_ device: AudioDevice, in category: OutputCategory?) -> Bool {
        device.isConnected && !priorityManager.isNeverUse(device) && !isDeviceIgnored(device, inCategory: category)
    }

    /// Picks by priority again after a change to the lists; `connected` names devices that
    /// have just become available. Does nothing while automatic switching is paused.
    private func pickAgain(_ type: AudioDeviceType, connected: Set<String> = []) {
        guard !isCustomMode, !isDeviceReadUnavailable else { return }
        // Preserve pending manual intent, but let a newly available higher priority
        // endpoint supersede an automatic request. Duplicate events keep its budget.
        guard pendingRoutes[type]?.manual != true else { return }
        if type == .output { autoSwitchModeIfNeeded(newlyConnectedRowIDs: connected) }
        if let pending = pendingRoutes[type] {
            let list = type == .input ? inputDevices : activeOutputDevices
            let category: OutputCategory? = type == .input ? nil : currentMode
            let desired = list.first { canPickAutomatically($0, in: category) }
            guard desired?.rowID != pending.device.rowID else { return }
            cancelRoute(type)
        }
        switch type {
        case .input:
            applyHighestPriorityInput()
        case .output:
            applyHighestPriorityOutput()
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

    @discardableResult
    func refreshDevices() -> Bool {
        guard case .available(let allConnectedDevices) = deviceService.readInventory() else {
            isDeviceReadUnavailable = true
            batteryLevels = [:]
            batteryGeneration += 1
            batteryLastAttempt = nil
            scheduleInventoryRecovery()
            return false
        }
        isDeviceReadUnavailable = false
        inventoryRetry?.cancel()
        inventoryRetry = nil
        inventoryRetryCount = 0
        // Ignore names/volume when deciding whether a new topology permits another attempt.
        let topology = Set(allConnectedDevices.map { "\($0.rowID):\($0.id)" })
        if topology != Set(connectedDevices.map { "\($0.rowID):\($0.id)" }) { failedRows = [:] }
        let oldBatteryEndpoints = Set(connectedDevices.filter { DeviceBattery.address(for: $0) != nil }.map { "\($0.rowID):\($0.id)" })
        let newBatteryEndpoints = Set(allConnectedDevices.filter { DeviceBattery.address(for: $0) != nil }.map { "\($0.rowID):\($0.id)" })
        if oldBatteryEndpoints != newBatteryEndpoints {
            batteryGeneration += 1
            batteryLastAttempt = nil
            batteryReadAt = nil
            batteryLevels = [:]
        }
        connectedDevices = allConnectedDevices
        connectedRowIDs = Set(allConnectedDevices.map { $0.rowID })
        priorityManager.rememberDevices(allConnectedDevices)
        let connectedInputs = allConnectedDevices.filter { $0.type == .input }
        let connectedOutputs = allConnectedDevices.filter { $0.type == .output }
        let inputInUse = deviceService.getCurrentDefaultDevice(type: .input)
        let outputInUse = deviceService.getCurrentDefaultDevice(type: .output)

        if isEditMode {
            let knownDevices = priorityManager.getKnownDevices()
            var allInputs: [AudioDevice] = connectedInputs
            for stored in knownDevices where stored.isInput {
                if !connectedRowIDs.contains("input:\(stored.uid)") {
                    allInputs.append(.disconnected(uid: stored.uid, name: stored.name, type: .input))
                }
            }
            var allOutputs: [AudioDevice] = connectedOutputs
            for stored in knownDevices where !stored.isInput {
                if !connectedRowIDs.contains("output:\(stored.uid)") {
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
        refreshListeningModes()
        return true
    }

    func refreshListeningModes() {
        let outputs = connectedDevices.filter { $0.type == .output }
        let candidates = outputs.filter(\.isListeningModeCandidate)
        let endpoints = Dictionary(candidates.map { ($0.uid, $0.id) }, uniquingKeysWith: { first, _ in first })
        if endpoints != listeningModeEndpoints {
            modeRecovery?.cancel()
            modeRecovery = nil
            modeRecoveryCount = 0
            for (uid, request) in Array(modeRequests) where endpoints[uid] != request.device.id {
                finishModeRequest(uid, failure: nil)
            }
            listeningModeRequests = listeningModeRequests.filter {
                endpoints[$0.key] != nil && endpoints[$0.key] == listeningModeEndpoints[$0.key]
            }
        }
        listeningModeService.observe(outputs)
        var next: [String: ListeningModeState] = [:]
        var unavailable: Set<String> = []
        for device in candidates {
            if let state = listeningModeService.state(for: device) {
                next[device.uid] = state
            } else {
                unavailable.insert(device.uid)
                // Keep controls discoverable after a transient read failure, but do
                // not keep a stale checkmark or allow a write from cached capability.
                if listeningModeEndpoints[device.uid] == device.id {
                    next[device.uid] = listeningModes[device.uid]?.withoutCurrent
                }
            }
        }
        listeningModeEndpoints = endpoints
        if next != listeningModes { listeningModes = next }
        if unavailable != unavailableListeningModeUIDs { unavailableListeningModeUIDs = unavailable }
        for (uid, request) in Array(modeRequests) {
            if next[uid]?.current == request.mode {
                finishModeRequest(uid, failure: nil)
            } else if let state = next[uid], !unavailable.contains(uid), !state.supported.contains(request.mode) {
                finishModeRequest(uid, failure: .unavailable)
            }
        }
        // A later notification may report a timed-out request's target. Reflect that
        // system state without treating it as a hardware acknowledgement.
        for (uid, state) in Array(listeningModeRequests) {
            if case .failed(let mode, _) = state, next[uid]?.current == mode {
                listeningModeRequests[uid] = nil
            }
        }
        if !unavailable.isEmpty || listeningModeService.needsObservationRecovery {
            scheduleModeRecovery()
        } else {
            modeRecovery?.cancel()
            modeRecovery = nil
            modeRecoveryCount = 0
        }
    }

    private func scheduleModeRecovery() {
        guard modeRecovery == nil, modeRecoveryCount < modeRecoveryDelays.count else { return }
        let delay = modeRecoveryDelays[modeRecoveryCount]
        modeRecoveryCount += 1
        modeRecovery = scheduler.schedule(after: delay) { [weak self] in
            guard let self else { return }
            self.modeRecovery = nil
            self.refreshListeningModes()
        }
    }

    func retryListeningModeRead() {
        modeRecovery?.cancel()
        modeRecovery = nil
        modeRecoveryCount = 0
        refreshListeningModes()
    }

    /// One accepted write, followed by bounded read-backs. Only an explicit retry
    /// writes again. Neither completion nor failure changes routing or priorities.
    @discardableResult
    func setListeningMode(_ mode: ListeningMode, for device: AudioDevice) -> Bool {
        guard modeRequests[device.uid] == nil else { return false }
        guard let currentDevice = connectedDevices.first(where: { $0.rowID == device.rowID && $0.id == device.id }),
              currentDevice.isListeningModeCandidate else { return false }
        // The mode service validates identity directly, independently of a failed
        // full inventory read. Retrying this control must never trigger routing.
        guard let state = listeningModeService.state(for: currentDevice), state.supported.contains(mode) else {
            listeningModeRequests[device.uid] = .failed(mode, .unavailable)
            refreshListeningModes()
            return false
        }
        if state.current == mode {
            listeningModeRequests[device.uid] = nil
            refreshListeningModes()
            return true
        }
        let request = ModeRequest(device: currentDevice, mode: mode)
        modeRequests[device.uid] = request
        listeningModeRequests[device.uid] = .pending(mode)
        guard listeningModeService.request(mode, for: currentDevice) else {
            finishModeRequest(device.uid, failure: .rejected)
            refreshListeningModes()
            return false
        }
        refreshListeningModes()
        scheduleModeReadback(request)
        return true
    }

    func retryListeningMode(for device: AudioDevice) {
        guard case .failed(let mode, _) = listeningModeRequests[device.uid] else { return }
        setListeningMode(mode, for: device)
    }

    private func scheduleModeReadback(_ request: ModeRequest) {
        let uid = request.device.uid
        guard modeRequests[uid] === request else { return }
        guard request.readbacks < modeReadbackDelays.count else {
            finishModeRequest(uid, failure: .timedOut)
            return
        }
        let delay = modeReadbackDelays[request.readbacks]
        request.readbacks += 1
        request.scheduled = scheduler.schedule(after: delay) { [weak self, weak request] in
            guard let self, let request, self.modeRequests[uid] === request else { return }
            request.scheduled = nil
            self.refreshListeningModes()
            self.scheduleModeReadback(request)
        }
    }

    private func finishModeRequest(_ uid: String, failure: ListeningModeFailure?) {
        guard let request = modeRequests.removeValue(forKey: uid) else { return }
        request.scheduled?.cancel()
        listeningModeRequests[uid] = failure.map { .failed(request.mode, $0) }
    }

    func toggleEditMode() {
        isEditMode.toggle()
        refreshDevices()
    }

    /// Track each endpoint independently, including duplex devices with a shared UID.
    private var previousConnectedRowIDs: Set<String> = []
    
    func setCustomMode(_ enabled: Bool) {
        for type in Array(pendingRoutes.keys) { cancelRoute(type) }
        failedRows = [:]
        routingFailure = nil
        handPickedUIDs = [:]
        isCustomMode = enabled
        priorityManager.isCustomMode = enabled
        needsOutputReconciliation = !enabled
        if !enabled {
            // Always refresh before resuming, including after a missed event.
            guard refreshDevices() else { return }
            followOutputInUse()
            needsOutputReconciliation = false
            pickAgain(.input)
            pickAgain(.output)
        }
    }

    func setCategory(_ category: OutputCategory, for device: AudioDevice) {
        cancelRoute(device.type)
        failedRows[device.type] = []
        let previous = priorityManager.getCategory(for: device)
        let wasInUse = device.isConnected && device.id == currentOutputId
        priorityManager.setCategory(category, for: device)
        refreshDevices()
        guard !isCustomMode else { return }
        if category != previous {
            followCategoryChange(of: device, to: category, wasInUse: wasInUse)
        }
        pickAgain(.output)
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
        } else if category == .headphone, canPickAutomatically(list[index], in: .headphone) {
            // The same as headphones that have just been connected
            handPickedUIDs[.output] = nil
            switchMode(to: .headphone)
        }
    }

    func hideDevice(_ device: AudioDevice, category: OutputCategory? = nil) {
        cancelRoute(device.type)
        failedRows[device.type] = []
        if device.type == .input {
            priorityManager.hideDevice(device)
        } else if let cat = category {
            priorityManager.hideDevice(device, inCategory: cat)
        } else {
            priorityManager.hideDevice(device)
        }
        refreshDevices()
        pickAgain(device.type)
    }

    func hideDeviceEntirely(_ device: AudioDevice) {
        cancelRoute(device.type)
        failedRows[device.type] = []
        priorityManager.hideDevice(device, inCategory: .speaker)
        priorityManager.hideDevice(device, inCategory: .headphone)
        refreshDevices()
        pickAgain(.output)
    }

    func unhideDevice(_ device: AudioDevice) {
        cancelRoute(device.type)
        failedRows[device.type] = []
        priorityManager.unhideDevice(device)
        refreshDevices()
        // A device that is listed again is picked if it ranks first, like one just connected
        pickAgain(device.type, connected: [device.rowID])
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
        cancelRoute(device.type)
        failedRows[device.type] = []
        priorityManager.setNeverUse(device, neverUse: neverUse)
        refreshDevices()
        pickAgain(device.type)
    }

    func forgetDevice(_ device: AudioDevice) {
        cancelRoute(device.type)
        failedRows[device.type] = []
        priorityManager.forgetDevice(device)
        refreshDevices()
    }

    func moveInputDevice(_ move: DeviceMove) {
        guard let position = move.resolve(in: inputDevices) else { return }
        moveInputDevice(from: position.source, to: position.destination)
    }

    func moveInputDevice(from source: IndexSet, to destination: Int) {
        guard let moved = devices(at: source, movingTo: destination, in: inputDevices) else { return }
        cancelRoute(.input)
        failedRows[.input] = []
        inputDevices.move(fromOffsets: source, toOffset: destination)
        priorityManager.savePriorities(inputDevices, moved: moved, type: .input)
        // Switch to top input if it's connected
        if let topInput = deviceToUseAfterMove(in: inputDevices, category: nil) {
            applyInputDevice(topInput)
        }
    }

    func moveSpeakerDevice(_ move: DeviceMove) {
        guard let position = move.resolve(in: speakerDevices) else { return }
        moveSpeakerDevice(from: position.source, to: position.destination)
    }

    func moveSpeakerDevice(from source: IndexSet, to destination: Int) {
        guard let moved = devices(at: source, movingTo: destination, in: speakerDevices) else { return }
        cancelRoute(.output)
        failedRows[.output] = []
        speakerDevices.move(fromOffsets: source, toOffset: destination)
        priorityManager.savePriorities(speakerDevices, moved: moved, category: .speaker)
        // Switch to top speaker only if we're in speaker mode and top speaker is connected
        if currentMode == .speaker, let topSpeaker = deviceToUseAfterMove(in: speakerDevices, category: .speaker) {
            applyOutputDevice(topSpeaker)
        }
    }

    func moveHeadphoneDevice(_ move: DeviceMove) {
        guard let position = move.resolve(in: headphoneDevices) else { return }
        moveHeadphoneDevice(from: position.source, to: position.destination)
    }

    func moveHeadphoneDevice(from source: IndexSet, to destination: Int) {
        guard let moved = devices(at: source, movingTo: destination, in: headphoneDevices) else { return }
        cancelRoute(.output)
        failedRows[.output] = []
        headphoneDevices.move(fromOffsets: source, toOffset: destination)
        priorityManager.savePriorities(headphoneDevices, moved: moved, category: .headphone)
        // Switch to top headphone only if we're in headphone mode and it's connected
        if currentMode == .headphone, let topHeadphone = deviceToUseAfterMove(in: headphoneDevices, category: .headphone) {
            applyOutputDevice(topHeadphone)
        }
    }

    /// The devices about to move, or nil when the list changed under a drag and the places no longer exist
    private func devices(at source: IndexSet, movingTo destination: Int, in list: [AudioDevice]) -> [AudioDevice]? {
        guard source.allSatisfy(list.indices.contains), (0...list.count).contains(destination) else { return nil }
        return source.map { list[$0] }
    }

    /// Reordering a list puts to use the first device in it that the app may pick by itself.
    /// A device picked by hand stays in use, and nothing changes while automatic switching
    /// is paused. `category` is nil for the microphones.
    private func deviceToUseAfterMove(in list: [AudioDevice], category: OutputCategory?) -> AudioDevice? {
        guard !isCustomMode, !isDeviceReadUnavailable, !isKeepingHandPick(category == nil ? .input : .output) else { return nil }
        return list.first { canPickAutomatically($0, in: category) }
    }

    /// Manual selection and promotion form one operation, completed after read-back.
    func selectOutputDevice(_ device: AudioDevice, in category: OutputCategory) {
        requestRoute(device, manual: true, category: category)
    }

    func setInputDevice(_ device: AudioDevice) {
        requestRoute(device, manual: true, category: nil)
    }

    func setOutputDevice(_ device: AudioDevice) {
        requestRoute(device, manual: true, category: priorityManager.getCategory(for: device))
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

    private func applyInputDevice(_ device: AudioDevice) {
        requestRoute(device, manual: false, category: nil)
    }

    private func applyOutputDevice(_ device: AudioDevice) {
        requestRoute(device, manual: false, category: currentMode)
    }

    private func applyHighestPriorityInput() {
        guard !isKeepingHandPick(.input) else { return }
        let eligible = inputDevices.filter { canPickAutomatically($0, in: nil) }
        if let target = RoutingPolicy.candidate(in: eligible, failedRowIDs: failedRows[.input] ?? [],
            currentID: currentInputId, connected: connectedDevices, type: .input) {
            applyInputDevice(target)
        }
    }

    private func applyHighestPriorityOutput() {
        guard !isKeepingHandPick(.output) else { return }
        let eligible = activeOutputDevices.filter { canPickAutomatically($0, in: currentMode) }
        if let target = RoutingPolicy.candidate(in: eligible, failedRowIDs: failedRows[.output] ?? [],
            currentID: currentOutputId, connected: connectedDevices, type: .output) {
            applyOutputDevice(target)
        }
        refreshMuteStatus()
    }

    private func cancelRoute(_ type: AudioDeviceType) {
        pendingRoutes.removeValue(forKey: type)?.scheduled?.cancel()
        pendingRouteRows = Set(pendingRoutes.values.map { $0.device.rowID })
    }

    private func requestRoute(_ device: AudioDevice, manual: Bool, category: OutputCategory?) {
        guard device.isConnected, manual || (!isCustomMode && !isDeviceReadUnavailable) else { return }
        if !manual {
            guard pendingRoutes[device.type] == nil, !(failedRows[device.type] ?? []).contains(device.rowID) else { return }
        } else {
            cancelRoute(device.type)
            failedRows[device.type] = []
            routingFailure = nil
        }
        let request = RouteRequest(device: device, manual: manual, category: category,
                                   promote: manual && !isCustomMode)
        pendingRoutes[device.type] = request
        pendingRouteRows = Set(pendingRoutes.values.map { $0.device.rowID })
        attemptRoute(request)
    }

    private func attemptRoute(_ request: RouteRequest) {
        let type = request.device.type
        guard pendingRoutes[type]?.id == request.id else { return }
        guard request.manual || !isCustomMode else { cancelRoute(type); return }
        request.attempts += 1
        guard refreshDevices() else { scheduleRouteRetry(request); return }
        guard let device = connectedDevices.first(where: { $0.rowID == request.device.rowID }) else {
            finishFailure(request)
            return
        }
        if !request.manual && !canPickAutomatically(device, in: request.category) {
            cancelRoute(type)
            return
        }
        // A failed default-device read cannot justify a write.
        guard let actual = deviceService.getCurrentDefaultDevice(type: type) else {
            scheduleRouteRetry(request)
            return
        }
        if actual == device.id {
            completeRoute(request, device: device)
            return
        }
        _ = deviceService.setDefaultDevice(device)
        if deviceService.getCurrentDefaultDevice(type: type) == device.id {
            completeRoute(request, device: device)
        } else {
            scheduleRouteRetry(request)
        }
    }

    private func scheduleRouteRetry(_ request: RouteRequest) {
        // Check once after the final write too: HAL may accept a write asynchronously.
        let delay = request.attempts <= retryDelays.count ? retryDelays[request.attempts - 1] : 0.3
        request.scheduled?.cancel()
        request.scheduled = scheduler.schedule(after: delay) { [weak self] in
            guard let self, self.pendingRoutes[request.device.type]?.id == request.id else { return }
            if request.attempts <= self.retryDelays.count {
                self.attemptRoute(request)
            } else if self.refreshDevices(),
                      let device = self.connectedDevices.first(where: { $0.rowID == request.device.rowID }),
                      self.deviceService.getCurrentDefaultDevice(type: device.type) == device.id {
                self.completeRoute(request, device: device)
            } else {
                self.finishFailure(request)
            }
        }
    }

    private func completeRoute(_ request: RouteRequest, device: AudioDevice) {
        cancelRoute(device.type)
        if device.type == .input { currentInputId = device.id } else { currentOutputId = device.id }
        if request.manual {
            handPickedUIDs[device.type] = priorityManager.isNeverUse(device) ? device.uid : nil
            if request.promote {
                if let category = request.category { switchMode(to: category) }
                promoteConfirmedDevice(device, category: request.category)
            }
        }
        if routingFailure?.device.type == device.type { routingFailure = nil }
        refreshVolume()
        refreshMuteStatus()
    }

    private func promoteConfirmedDevice(_ device: AudioDevice, category: OutputCategory?) {
        var list = device.type == .input ? inputDevices : (category == .headphone ? headphoneDevices : speakerDevices)
        guard let index = list.firstIndex(where: { $0.rowID == device.rowID }), index > 0 else { return }
        list.insert(list.remove(at: index), at: 0)
        if device.type == .input {
            priorityManager.savePriorities(list, moved: [device], type: .input)
            inputDevices = list
        } else if let category {
            priorityManager.savePriorities(list, moved: [device], category: category)
            if category == .headphone { headphoneDevices = list } else { speakerDevices = list }
        }
    }

    private func finishFailure(_ request: RouteRequest) {
        guard pendingRoutes[request.device.type]?.id == request.id else { return }
        cancelRoute(request.device.type)
        failedRows[request.device.type, default: []].insert(request.device.rowID)
        routingFailure = RoutingFailure(device: request.device, manual: request.manual, category: request.category)
        // Only automatic requests may fall back, and only with a confirmed inventory
        // and no currently available route. The policy enforces both constraints.
        if !request.manual && !isDeviceReadUnavailable { pickAgain(request.device.type) }
    }

    func retryRoutingFailure(_ dismissedFailure: RoutingFailure? = nil) {
        guard let failure = dismissedFailure ?? routingFailure else { return }
        failedRows[failure.device.type] = []
        routingFailure = nil
        if failure.manual {
            requestRoute(failure.device, manual: true, category: failure.category)
        } else if refreshDevices() {
            pickAgain(failure.device.type)
        }
    }

    private func scheduleInventoryRecovery() {
        guard inventoryRetry == nil, inventoryRetryCount < retryDelays.count else { return }
        let delay = retryDelays[inventoryRetryCount]
        inventoryRetryCount += 1
        inventoryRetry = scheduler.schedule(after: delay) { [weak self] in
            guard let self else { return }
            self.inventoryRetry = nil
            self.handleDeviceChange()
        }
    }

    func retryDeviceRead() {
        inventoryRetry?.cancel()
        inventoryRetry = nil
        inventoryRetryCount = 0
        handleDeviceChange()
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
        let oldConnectedRows = previousConnectedRowIDs
        let inventoryReady = refreshDevices()
        refreshVolume()
        refreshMuteStatus()
        guard inventoryReady else { return }

        // Detect newly connected devices
        var newlyConnectedRowIDs = connectedRowIDs.subtracting(oldConnectedRows)
        previousConnectedRowIDs = connectedRowIDs
        // "Last seen" is when a device went away, not when the list was last read with it in it
        priorityManager.markLastSeen(rowIDs: oldConnectedRows.subtracting(connectedRowIDs))

        if !isCustomMode && needsOutputReconciliation {
            // Startup/resume may have failed its first read. Treat recovery as the
            // initial snapshot, not as every already-connected headphone arriving.
            followOutputInUse()
            needsOutputReconciliation = false
            newlyConnectedRowIDs = []
        }

        for request in Array(pendingRoutes.values) {
            guard let device = connectedDevices.first(where: { $0.rowID == request.device.rowID }) else {
                finishFailure(request)
                continue
            }
            if deviceService.getCurrentDefaultDevice(type: device.type) == device.id {
                completeRoute(request, device: device)
            }
        }

        // Auto-switch mode only when a new headphone connects or all headphones disconnect
        pickAgain(.input)
        pickAgain(.output, connected: newlyConnectedRowIDs)
    }

    /// Automatically switches between headphone and speaker mode based on device connections.
    /// Only triggers on:
    /// 1. A new headphone device connects → switch to headphone mode
    /// 2. All headphones disconnect → switch to speaker mode
    private func autoSwitchModeIfNeeded(newlyConnectedRowIDs: Set<String>) {
        // Only devices the app may pick count: connecting one marked "never select automatically" changes nothing
        let connectedHeadphones = headphoneDevices.filter { canPickAutomatically($0, in: .headphone) }
        let hasConnectedHeadphones = !connectedHeadphones.isEmpty
        let hasConnectedSpeakers = speakerDevices.contains { canPickAutomatically($0, in: .speaker) }
        
        // Check if a new headphone just connected
        let newHeadphoneConnected = connectedHeadphones.contains { newlyConnectedRowIDs.contains($0.rowID) }
        
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
