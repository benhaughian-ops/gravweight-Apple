import Foundation

/// Mirrors `com.gravweight.shared.PlateSystem`.
enum PlateSystem {
    case imperial
    case metric
}

/// Mirrors `com.gravweight.shared.PlateType` — same case names, weights and labels as Android.
enum PlateType: String, CaseIterable, Identifiable, Codable {
    // Imperial (LBS)
    case LB_45, LB_35, LB_25, LB_15, LB_10, LB_5, LB_2_5
    // Metric (KG)
    case KG_25, KG_20, KG_15, KG_10, KG_5, KG_2_5, KG_1_25

    var id: String { rawValue }

    var system: PlateSystem { rawValue.hasPrefix("LB") ? .imperial : .metric }

    var weight: Double {
        switch self {
        case .LB_45: return 45
        case .LB_35: return 35
        case .LB_25: return 25
        case .LB_15: return 15
        case .LB_10: return 10
        case .LB_5: return 5
        case .LB_2_5: return 2.5
        case .KG_25: return 25
        case .KG_20: return 20
        case .KG_15: return 15
        case .KG_10: return 10
        case .KG_5: return 5
        case .KG_2_5: return 2.5
        case .KG_1_25: return 1.25
        }
    }

    var displayLabel: String {
        switch self {
        case .LB_45: return "45 lb"
        case .LB_35: return "35 lb"
        case .LB_25: return "25 lb"
        case .LB_15: return "15 lb"
        case .LB_10: return "10 lb"
        case .LB_5: return " 5 lb"
        case .LB_2_5: return "2.5 lb"
        case .KG_25: return "25 kg"
        case .KG_20: return "20 kg"
        case .KG_15: return "15 kg"
        case .KG_10: return "10 kg"
        case .KG_5: return "5 kg"
        case .KG_2_5: return "2.5 kg"
        case .KG_1_25: return "1.25 kg"
        }
    }
}
