import Foundation

/// Mirrors `com.gravweight.shared.BarbellState`.
/// Bar is 45 lb / 20 kg; total = bar + 2 × Σ(plate × count) for the active system.
struct BarbellState: Equatable {
    var isMetric: Bool = false
    var plateCounts: [PlateType: Int] = Dictionary(uniqueKeysWithValues: PlateType.allCases.map { ($0, 0) })

    var barWeight: Double { isMetric ? 20.0 : 45.0 }
    var activeSystem: PlateSystem { isMetric ? .metric : .imperial }
    var activePlates: [PlateType] { PlateType.allCases.filter { $0.system == activeSystem } }

    var totalLoad: Double {
        var sum = 0.0
        for (type, count) in plateCounts where type.system == activeSystem {
            sum += type.weight * Double(count)
        }
        return barWeight + 2.0 * sum
    }

    var totalLoadLbs: Double { isMetric ? totalLoad * 2.2046226218 : totalLoad }

    var unitLabel: String { isMetric ? "KG" : "LBS" }

    /// "315" or "47.5"
    var totalLoadNumber: String {
        totalLoad.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(totalLoad)) : String(totalLoad)
    }

    /// "315 LBS" / "140 KG"
    var totalLoadDisplay: String { "\(totalLoadNumber) \(unitLabel)" }

    func count(_ plate: PlateType) -> Int { plateCounts[plate] ?? 0 }

    func addingPlate(_ plate: PlateType) -> BarbellState {
        var copy = self
        copy.plateCounts[plate] = count(plate) + 1
        return copy
    }

    func removingPlate(_ plate: PlateType) -> BarbellState {
        let current = count(plate)
        guard current > 0 else { return self }
        var copy = self
        copy.plateCounts[plate] = current - 1
        return copy
    }

    func cleared() -> BarbellState {
        var copy = self
        for key in PlateType.allCases { copy.plateCounts[key] = 0 }
        return copy
    }

    /// Same keys as Android's `toDataMap()`: `isMetric` (0/1) + one key per plate case name.
    func toDictionary() -> [String: Any] {
        var map: [String: Any] = [WatchKeys.isMetric: isMetric ? 1 : 0]
        for type in PlateType.allCases { map[type.rawValue] = count(type) }
        return map
    }

    static func from(_ map: [String: Any]) -> BarbellState {
        func int(_ key: String) -> Int {
            if let v = map[key] as? Int { return v }
            if let v = map[key] as? NSNumber { return v.intValue }
            return 0
        }
        var counts: [PlateType: Int] = [:]
        for type in PlateType.allCases { counts[type] = int(type.rawValue) }
        return BarbellState(isMetric: int(WatchKeys.isMetric) == 1, plateCounts: counts)
    }
}
