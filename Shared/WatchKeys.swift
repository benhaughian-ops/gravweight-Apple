import Foundation

/// WatchConnectivity message keys — the Apple equivalent of Android's `WearableKeys`.
/// Every payload carries a `kind` so both sides can route it.
enum WatchKeys {
    static let kind = "kind"

    /// Barbell state sync (phone ⇄ watch). Payload = `BarbellState.toDictionary()`.
    static let kindState = "/gravweight/state"
    /// Watch → phone: "log the current weight". Payload = weight (lbs), timestamp (ms), nonce.
    static let kindLogTrigger = "/gravweight/log_trigger"

    static let isMetric = "isMetric"
    static let timestamp = "timestamp"
    static let weight = "weight"
    static let nonce = "nonce"
}
