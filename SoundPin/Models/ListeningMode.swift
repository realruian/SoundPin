import Foundation

/// Private HAL values, validated on the connected device before every write.
/// A HAL read describes the system's cached state, not a hardware acknowledgement.
enum ListeningMode: UInt32, CaseIterable, Identifiable {
    case transparency = 3
    case adaptive = 4
    case noiseCancellation = 2

    var id: UInt32 { rawValue }
    var supportBit: UInt32 { 1 << (rawValue - 2) }

    var title: String {
        switch self {
        case .transparency: return L10n.transparency
        case .adaptive: return L10n.adaptive
        case .noiseCancellation: return L10n.noiseCancellation
        }
    }
}

struct ListeningModeState: Equatable {
    let current: ListeningMode?
    let supported: [ListeningMode]

    init(currentRawValue: UInt32, supportedMask: UInt32) {
        supported = ListeningMode.allCases.filter { supportedMask & $0.supportBit != 0 }
        // Off and future/unknown values leave all offered rows unchecked.
        if let mode = ListeningMode(rawValue: currentRawValue), supported.contains(mode) {
            current = mode
        } else {
            current = nil
        }
    }
}
