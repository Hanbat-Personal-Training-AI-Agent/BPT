import Foundation

enum NativePoseExercise: String, CaseIterable {
    case deadlift
    case benchPress
    case squat
    case barbellRow
    case pushUp

    /// Hands are overlay-only today. Skip the two auxiliary models for lower-body squat;
    /// preserve other exercises' overlays, with an explicit A/B override for profiling.
    func handBranchEnabled(override: Bool? = nil) -> Bool {
        override ?? (self != .squat)
    }

    init?(flutterId: String) {
        switch flutterId {
        case "deadlift":
            self = .deadlift
        case "benchpress":
            self = .benchPress
        case "squat":
            self = .squat
        case "barbell-row":
            self = .barbellRow
        case "pushup":
            self = .pushUp
        default:
            return nil
        }
    }

    var displayName: String {
        switch self {
        case .deadlift:
            return "Deadlift"
        case .benchPress:
            return "Bench Press"
        case .squat:
            return "Squat"
        case .barbellRow:
            return "Barbell Row"
        case .pushUp:
            return "Push Up"
        }
    }
}
