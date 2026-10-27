import Foundation
import CoreAudio

enum AudioDeviceType: String, Codable {
    case input
    case output
}

enum OutputCategory: String, Codable, CaseIterable {
    case speaker
    case headphone

    var label: String {
        switch self {
        case .speaker: return L10n.speakers
        case .headphone: return L10n.headphones
        }
    }
}

struct AudioDevice: Identifiable, Equatable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let type: AudioDeviceType
    var isConnected: Bool = true
    /// Captured with the inventory; models and previews never query HAL.
    var transportType: UInt32? = nil
    /// HAL capability survives user-renaming; false also keeps ordinary Bluetooth
    /// speakers out of listening-mode recovery. Existing sample devices use the name fallback.
    var listeningModeCapable: Bool = false

    /// Candidate filtering is local; the service still validates UID and HAL capability.
    var isListeningModeCandidate: Bool {
        isConnected && id != 0 && type == .output
            && (listeningModeCapable || name.localizedCaseInsensitiveContains("AirPods"))
            && transportType == kAudioDeviceTransportTypeBluetooth
    }

    /// Identity of a row in a list. `id` cannot serve: every disconnected device has id 0,
    /// and a device with both a microphone and a speaker has one id for the two.
    var rowID: String {
        "\(type.rawValue):\(uid)"
    }

    // Create a disconnected placeholder from stored device
    static func disconnected(uid: String, name: String, type: AudioDeviceType) -> AudioDevice {
        AudioDevice(id: 0, uid: uid, name: name, type: type, isConnected: false)
    }
}

/// A reorder captures endpoint identities and the list seen when the gesture began.
/// Topology or order changes cancel it; names and volume updates do not.
struct DeviceMove {
    struct Endpoint: Equatable {
        let rowID: String
        let id: AudioObjectID
        let isConnected: Bool
    }
    let rowID: String
    let beforeRowID: String?
    let snapshot: [Endpoint]

    static func identities(in devices: [AudioDevice]) -> [Endpoint] {
        devices.map { Endpoint(rowID: $0.rowID, id: $0.id, isConnected: $0.isConnected) }
    }

    init?(rowID: String, to destination: Int, in devices: [AudioDevice]) {
        guard let source = devices.firstIndex(where: { $0.rowID == rowID }),
              (0...devices.count).contains(destination),
              destination != source, destination != source + 1 else { return nil }
        self.rowID = rowID
        beforeRowID = destination < devices.count ? devices[destination].rowID : nil
        snapshot = Self.identities(in: devices)
    }

    func resolve(in devices: [AudioDevice]) -> (source: IndexSet, destination: Int)? {
        guard snapshot == Self.identities(in: devices),
              let source = devices.firstIndex(where: { $0.rowID == rowID }) else { return nil }
        let destination: Int
        if let beforeRowID {
            guard let index = devices.firstIndex(where: { $0.rowID == beforeRowID }) else { return nil }
            destination = index
        } else {
            destination = devices.count
        }
        return (IndexSet(integer: source), destination)
    }
}
