import IOKit.ps
import Core

/// A single, cheap read of the system's battery state via the public
/// IOPowerSources API (no entitlement, no permission prompt, no polling
/// loop of its own -- read once per existing housekeeping tick, exactly
/// like `IdleTimeReader`). Returns nil on a desktop Mac with no battery.
public enum BatteryReader {
    public struct State: Equatable {
        public let level: Double?
        public let isCharging: Bool
    }

    public static func read() -> State? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            guard (info[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let current = info[kIOPSCurrentCapacityKey] as? Int
            let max = info[kIOPSMaxCapacityKey] as? Int
            let level = (current.flatMap { c in max.map { m in m > 0 ? Double(c) / Double(m) : nil } }) ?? nil
            let charging = (info[kIOPSIsChargingKey] as? Bool) ?? false
            return State(level: level, isCharging: charging)
        }
        return nil // no internal battery (desktop Mac) -- not an error
    }
}
