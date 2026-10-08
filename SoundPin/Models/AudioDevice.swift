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

extension AudioDevice {
    /// How the device is attached (built-in, USB, Bluetooth, HDMI, ...); nil when it is not connected
    var transportType: UInt32? {
        guard isConnected else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }
}
