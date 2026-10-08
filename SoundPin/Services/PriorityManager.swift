import Foundation
import CoreAudio

struct StoredDevice: Codable, Equatable {
    let uid: String
    let name: String
    let isInput: Bool
    var lastSeen: Date

    var lastSeenRelative: String {
        let now = Date()
        let interval = now.timeIntervalSince(lastSeen)

        if interval < 60 {
            return L10n.justNow
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return L10n.minutesAgo(mins)
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return L10n.hoursAgo(hours)
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return L10n.daysAgo(days)
        } else if interval < 2592000 {
            let weeks = Int(interval / 604800)
            return L10n.weeksAgo(weeks)
        } else {
            let months = Int(interval / 2592000)
            return L10n.monthsAgo(months)
        }
    }
}

class PriorityManager {
    private let defaults = UserDefaults.standard

    private let inputPrioritiesKey = "inputPriorities"
    private let speakerPrioritiesKey = "speakerPriorities"
    private let headphonePrioritiesKey = "headphonePriorities"
    private let deviceCategoriesKey = "deviceCategories"
    private let currentModeKey = "currentMode"
    private let customModeKey = "customMode"
    private let knownDevicesKey = "knownDevices"

    // MARK: - Known Devices (Persistent Memory)

    func getKnownDevices() -> [StoredDevice] {
        guard let data = defaults.data(forKey: knownDevicesKey),
              let devices = try? JSONDecoder().decode([StoredDevice].self, from: data) else {
            return []
        }
        return devices
    }

    /// Records all connected devices in one pass, so the list is read and written once per refresh
    func rememberDevices(_ devices: [AudioDevice]) {
        guard !devices.isEmpty else { return }
        var known = getKnownDevices()
        let now = Date()
        for device in devices {
            let isInput = device.type == .input
            let stored = StoredDevice(uid: device.uid, name: device.name, isInput: isInput, lastSeen: now)
            // A device with both a microphone and a speaker has one UID for the two; each gets its own entry
            if let index = known.firstIndex(where: { $0.uid == device.uid && $0.isInput == isInput }) {
                // Update name and lastSeen
                known[index] = stored
            } else {
                known.append(stored)
            }
        }
        saveKnownDevices(known)
        rememberScreens(among: devices)
    }

    /// Sets "last seen" to now for devices that have just been disconnected
    func markLastSeen(uids: Set<String>) {
        guard !uids.isEmpty else { return }
        var known = getKnownDevices()
        let now = Date()
        for index in known.indices where uids.contains(known[index].uid) {
            known[index].lastSeen = now
        }
        saveKnownDevices(known)
    }

    /// What is remembered about this side of the device
    func getStoredDevice(for device: AudioDevice) -> StoredDevice? {
        let isInput = device.type == .input
        return getKnownDevices().first { $0.uid == device.uid && $0.isInput == isInput }
    }

    /// Forgets the device and everything set for this side of it, so that it starts afresh
    /// if it is ever connected again
    func forgetDevice(_ device: AudioDevice) {
        let isInput = device.type == .input
        var known = getKnownDevices()
        known.removeAll { $0.uid == device.uid && $0.isInput == isInput }
        saveKnownDevices(known)

        let lists = isInput
            ? [inputPrioritiesKey, hiddenMicsKey]
            : [speakerPrioritiesKey, headphonePrioritiesKey, hiddenSpeakersKey, hiddenHeadphonesKey]
        for key in lists {
            guard var list = defaults.array(forKey: key) as? [String], list.contains(device.uid) else { continue }
            list.removeAll { $0 == device.uid }
            // An empty order is no order: the list is then seeded again like a new one
            if list.isEmpty {
                defaults.removeObject(forKey: key)
            } else {
                defaults.set(list, forKey: key)
            }
        }
        if !isInput, var categories = defaults.dictionary(forKey: deviceCategoriesKey) as? [String: String],
           categories.removeValue(forKey: device.uid) != nil {
            defaults.set(categories, forKey: deviceCategoriesKey)
        }
        if isNeverUse(device) {
            setNeverUse(device, neverUse: false)
        }
    }

    private func saveKnownDevices(_ devices: [StoredDevice]) {
        if let data = try? JSONEncoder().encode(devices) {
            defaults.set(data, forKey: knownDevicesKey)
        }
    }

    // MARK: - Mode Management

    var currentMode: OutputCategory {
        get {
            guard let raw = defaults.string(forKey: currentModeKey),
                  let mode = OutputCategory(rawValue: raw) else {
                return .speaker
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: currentModeKey)
        }
    }

    var isCustomMode: Bool {
        get { defaults.bool(forKey: customModeKey) }
        set { defaults.set(newValue, forKey: customModeKey) }
    }

    // MARK: - Device Categories

    func getCategory(for device: AudioDevice) -> OutputCategory {
        let categories = defaults.dictionary(forKey: deviceCategoriesKey) as? [String: String] ?? [:]
        if let raw = categories[device.uid], let category = OutputCategory(rawValue: raw) {
            return category
        }
        // Default headphone-like devices to headphone category
        if HeadphoneDetection.isHeadphone(deviceName: device.name) {
            // A screen's audio is never headphones, whatever its name matches
            return isScreen(device) ? .speaker : .headphone
        }
        return .speaker
    }

    /// Attached over DisplayPort or HDMI. Known only while the device is connected.
    private func isScreen(_ device: AudioDevice) -> Bool {
        guard let transport = device.transportType else { return false }
        return transport == kAudioDeviceTransportTypeDisplayPort || transport == kAudioDeviceTransportTypeHDMI
    }

    /// A screen whose name reads like headphones is told apart by how it is attached, which
    /// cannot be asked once it is disconnected. The answer is stored while it can be had,
    /// so that the screen is listed with the speakers then too.
    private func rememberScreens(among devices: [AudioDevice]) {
        var categories = defaults.dictionary(forKey: deviceCategoriesKey) as? [String: String] ?? [:]
        var changed = false
        for device in devices where device.type == .output && categories[device.uid] == nil {
            if HeadphoneDetection.isHeadphone(deviceName: device.name) && isScreen(device) {
                categories[device.uid] = OutputCategory.speaker.rawValue
                changed = true
            }
        }
        if changed {
            defaults.set(categories, forKey: deviceCategoriesKey)
        }
    }

    func setCategory(_ category: OutputCategory, for device: AudioDevice) {
        var categories = defaults.dictionary(forKey: deviceCategoriesKey) as? [String: String] ?? [:]
        categories[device.uid] = category.rawValue
        defaults.set(categories, forKey: deviceCategoriesKey)
    }

    // MARK: - Never Use Devices (never auto-selected)

    private let neverUseKey = "neverUseDevices"

    // An entry is a row identity, so the microphone and the speaker of one device are
    // set apart. Entries written by 2.2.1 and earlier are a bare UID and cover both.

    func isNeverUse(_ device: AudioDevice) -> Bool {
        let list = defaults.array(forKey: neverUseKey) as? [String] ?? []
        return list.contains(device.rowID) || list.contains(device.uid)
    }

    func setNeverUse(_ device: AudioDevice, neverUse: Bool) {
        var list = defaults.array(forKey: neverUseKey) as? [String] ?? []
        // An older entry stays in force for the other side only, so that this side changes by itself
        if let index = list.firstIndex(of: device.uid) {
            let otherSide: AudioDeviceType = device.type == .input ? .output : .input
            list[index] = "\(otherSide.rawValue):\(device.uid)"
        }
        list.removeAll { $0 == device.rowID }
        if neverUse {
            list.append(device.rowID)
        }
        defaults.set(list, forKey: neverUseKey)
    }

    // MARK: - Hidden Devices (per category)

    private let hiddenMicsKey = "hiddenMics"
    private let hiddenSpeakersKey = "hiddenSpeakers"
    private let hiddenHeadphonesKey = "hiddenHeadphones"

    func isHidden(_ device: AudioDevice) -> Bool {
        let key = hiddenKey(for: device)
        let hidden = defaults.array(forKey: key) as? [String] ?? []
        return hidden.contains(device.uid)
    }

    func isHidden(_ device: AudioDevice, inCategory category: OutputCategory) -> Bool {
        let key = category == .speaker ? hiddenSpeakersKey : hiddenHeadphonesKey
        let hidden = defaults.array(forKey: key) as? [String] ?? []
        return hidden.contains(device.uid)
    }

    func hideDevice(_ device: AudioDevice) {
        let key = hiddenKey(for: device)
        var hidden = defaults.array(forKey: key) as? [String] ?? []
        if !hidden.contains(device.uid) {
            hidden.append(device.uid)
            defaults.set(hidden, forKey: key)
        }
    }

    func hideDevice(_ device: AudioDevice, inCategory category: OutputCategory) {
        let key = category == .speaker ? hiddenSpeakersKey : hiddenHeadphonesKey
        var hidden = defaults.array(forKey: key) as? [String] ?? []
        if !hidden.contains(device.uid) {
            hidden.append(device.uid)
            defaults.set(hidden, forKey: key)
        }
    }

    /// Stops ignoring the device. An output is taken off both lists: it may have been
    /// ignored in each, and would otherwise vanish again when moved to the other one.
    func unhideDevice(_ device: AudioDevice) {
        let keys = device.type == .input ? [hiddenMicsKey] : [hiddenSpeakersKey, hiddenHeadphonesKey]
        for key in keys {
            guard var hidden = defaults.array(forKey: key) as? [String], hidden.contains(device.uid) else { continue }
            hidden.removeAll { $0 == device.uid }
            defaults.set(hidden, forKey: key)
        }
    }

    private func hiddenKey(for device: AudioDevice) -> String {
        if device.type == .input {
            return hiddenMicsKey
        } else {
            let category = getCategory(for: device)
            return category == .speaker ? hiddenSpeakersKey : hiddenHeadphonesKey
        }
    }

    // MARK: - Priority Management

    func sortByPriority(_ devices: [AudioDevice], type: AudioDeviceType) -> [AudioDevice] {
        let key = priorityKey(for: type, category: nil)
        return sortDevices(devices, usingKey: key)
    }

    func sortByPriority(_ devices: [AudioDevice], category: OutputCategory) -> [AudioDevice] {
        let key = priorityKey(for: .output, category: category)
        return sortDevices(devices, usingKey: key)
    }

    /// Stores the new order after `moved` changed places in `devices`, the list on screen
    func savePriorities(_ devices: [AudioDevice], moved: [AudioDevice], type: AudioDeviceType) {
        let key = priorityKey(for: type, category: nil)
        savePriorities(devices, moved: moved, key: key)
    }

    func savePriorities(_ devices: [AudioDevice], moved: [AudioDevice], category: OutputCategory) {
        let key = priorityKey(for: .output, category: category)
        savePriorities(devices, moved: moved, key: key)
    }

    /// A list that has never been ordered starts with the device in use on top, so that
    /// the app's first pick from it is the device the Mac is using already. Does nothing
    /// once the list has an order, or while the device in use is not in it.
    func seedPriorities(_ devices: [AudioDevice], inUse: AudioObjectID?, type: AudioDeviceType) {
        seedPriorities(devices, inUse: inUse, key: priorityKey(for: type, category: nil))
    }

    func seedPriorities(_ devices: [AudioDevice], inUse: AudioObjectID?, category: OutputCategory) {
        seedPriorities(devices, inUse: inUse, key: priorityKey(for: .output, category: category))
    }

    private func seedPriorities(_ devices: [AudioDevice], inUse: AudioObjectID?, key: String) {
        guard defaults.object(forKey: key) == nil,
              let top = devices.first(where: { $0.isConnected && $0.id == inUse }) else { return }
        defaults.set([top.uid] + devices.map { $0.uid }.filter { $0 != top.uid }, forKey: key)
    }

    /// The stored order with `moved` put where it now sits among `shown`, the devices on
    /// screen. That list leaves out devices that are disconnected or ignored, so it cannot
    /// replace the stored order: those devices keep their rank, and only the moved one
    /// changes places. A device never ranked before comes last, as it is listed.
    static func reorder(_ stored: [String], shown: [String], moved: String) -> [String] {
        guard let position = shown.firstIndex(of: moved) else { return stored }
        var order: [String] = []
        for uid in stored + shown where uid != moved && !order.contains(uid) {
            order.append(uid)
        }
        if position + 1 < shown.count, let next = order.firstIndex(of: shown[position + 1]) {
            order.insert(moved, at: next)
        } else if position > 0, let previous = order.firstIndex(of: shown[position - 1]) {
            order.insert(moved, at: previous + 1)
        } else {
            order.append(moved)
        }
        return order
    }

    // MARK: - Private Helpers

    private func priorityKey(for type: AudioDeviceType, category: OutputCategory?) -> String {
        switch type {
        case .input:
            return inputPrioritiesKey
        case .output:
            switch category {
            case .speaker, .none:
                return speakerPrioritiesKey
            case .headphone:
                return headphonePrioritiesKey
            }
        }
    }

    private func sortDevices(_ devices: [AudioDevice], usingKey key: String) -> [AudioDevice] {
        let priorities = defaults.array(forKey: key) as? [String] ?? []

        return devices.sorted { a, b in
            let indexA = priorities.firstIndex(of: a.uid) ?? Int.max
            let indexB = priorities.firstIndex(of: b.uid) ?? Int.max
            return indexA < indexB
        }
    }

    private func savePriorities(_ devices: [AudioDevice], moved: [AudioDevice], key: String) {
        var order = defaults.array(forKey: key) as? [String] ?? []
        let shown = devices.map { $0.uid }
        // Last first, so that each one finds the device after it already in place
        for device in moved.reversed() {
            order = Self.reorder(order, shown: shown, moved: device.uid)
        }
        defaults.set(order, forKey: key)
    }
}
