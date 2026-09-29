import Foundation

public struct PerformanceSample {
    public let timestamp: Date
    public let residentMemoryBytes: UInt64
    public let cpuPercent: Double
    public let currentState: String
    public let currentAnimationFPS: Double
    public let uptimeSeconds: Double
}

/// Measures actual resident memory (via mach_task_basic_info) and actual CPU
/// usage (via getrusage, expressed as a percentage of wall-clock time since
/// the previous sample) for this process. These are real OS-reported values,
/// not estimates.
public final class PerformanceSampler {
    private let startTime = Date()
    private var lastCPUTimeSeconds: Double
    private var lastSampleDate: Date

    public init() {
        lastCPUTimeSeconds = Self.currentCPUTimeSeconds()
        lastSampleDate = Date()
    }

    public func sample(currentState: String, currentAnimationFPS: Double) -> PerformanceSample {
        let now = Date()
        let elapsedWall = now.timeIntervalSince(lastSampleDate)
        let cpuNow = Self.currentCPUTimeSeconds()
        let cpuDelta = cpuNow - lastCPUTimeSeconds
        let cpuPercent = elapsedWall > 0 ? min(100, max(0, (cpuDelta / elapsedWall) * 100)) : 0

        lastCPUTimeSeconds = cpuNow
        lastSampleDate = now

        return PerformanceSample(
            timestamp: now,
            residentMemoryBytes: Self.currentResidentMemoryBytes(),
            cpuPercent: cpuPercent,
            currentState: currentState,
            currentAnimationFPS: currentAnimationFPS,
            uptimeSeconds: now.timeIntervalSince(startTime)
        )
    }

    private static func currentResidentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }

    private static func currentCPUTimeSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        return user + system
    }
}
