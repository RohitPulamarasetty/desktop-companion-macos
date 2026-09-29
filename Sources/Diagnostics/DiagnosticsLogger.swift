import Foundation

/// Appends one line per sample to a local log file, so a multi-hour soak
/// test can be reviewed afterward without keeping any UI open. Never
/// uploaded anywhere; purely local diagnostics.
///
/// Bounded: when the file passes `maxBytes` it is rotated to
/// `diagnostics.log.1` (one generation kept), so an always-on app can't
/// grow the log forever (the previous version never rotated).
public final class DiagnosticsLogger {
    private var handle: FileHandle?
    public let fileURL: URL
    private let maxBytes: UInt64
    private var bytesWritten: UInt64 = 0
    private let formatter = ISO8601DateFormatter() // reused, not allocated per line

    public init(fileURL: URL, maxBytes: UInt64 = 2_000_000) {
        self.fileURL = fileURL
        self.maxBytes = maxBytes
        openHandle()
    }

    private func openHandle() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: fileURL)
        bytesWritten = (try? handle?.seekToEnd()) ?? 0
    }

    public func log(_ sample: PerformanceSample) {
        let megabytes = Double(sample.residentMemoryBytes) / 1_048_576
        let line = String(
            format: "%@\tRSS_MB=%.2f\tCPU_PCT=%.2f\tSTATE=%@\tANIM_FPS=%.1f\tUPTIME_S=%.0f\n",
            formatter.string(from: sample.timestamp),
            megabytes, sample.cpuPercent, sample.currentState, sample.currentAnimationFPS, sample.uptimeSeconds
        )
        let data = Data(line.utf8)
        handle?.write(data)
        bytesWritten += UInt64(data.count)
        if bytesWritten > maxBytes { rotate() }
    }

    private func rotate() {
        try? handle?.close()
        let old = fileURL.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: fileURL, to: old)
        openHandle()
    }

    public func close() {
        try? handle?.close()
    }
}
