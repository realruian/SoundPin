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

/// Request progress is separate from the last mode reported by the system.
enum ListeningModeRequestState: Equatable {
    case pending(ListeningMode)
    case failed(ListeningMode, ListeningModeFailure)

    var mode: ListeningMode {
        switch self {
        case .pending(let mode), .failed(let mode, _): return mode
        }
    }
    var isPending: Bool {
        if case .pending = self { return true }
        return false
    }
}

enum ListeningModeFailure: Equatable {
    case rejected
    case timedOut
    case unavailable

    var message: String {
        switch self {
        case .rejected: return L10n.listeningModeFailed
        case .timedOut: return L10n.listeningModeTimedOut
        case .unavailable: return L10n.listeningModeUnavailable
        }
    }
}

extension ListeningModeState {
    var withoutCurrent: ListeningModeState {
        ListeningModeState(currentRawValue: 0, supportedMask: supported.reduce(0) { $0 | $1.supportBit })
    }
}
