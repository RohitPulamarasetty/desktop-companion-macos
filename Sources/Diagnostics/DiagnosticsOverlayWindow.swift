import AppKit

/// A small on-demand overlay (toggled from the menu bar, not shown by
/// default) showing the live diagnostics numbers. It's a plain titled
/// NSPanel, not part of the always-on companion window.
public final class DiagnosticsOverlayWindow: NSPanel {
    private let label = NSTextField(labelWithString: "Diagnostics loading…")

    public init() {
        let rect = NSRect(x: 100, y: 100, width: 280, height: 140)
        super.init(contentRect: rect, styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        title = "Diagnostics"
        isReleasedWhenClosed = false

        label.frame = NSRect(x: 14, y: 14, width: 252, height: 112)
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.maximumNumberOfLines = 6
        label.lineBreakMode = .byWordWrapping
        contentView?.addSubview(label)
    }

    public func update(with sample: PerformanceSample) {
        let megabytes = Double(sample.residentMemoryBytes) / 1_048_576
        label.stringValue = """
        RSS:    \(String(format: "%.2f", megabytes)) MB
        CPU:    \(String(format: "%.2f", sample.cpuPercent)) %
        State:  \(sample.currentState)
        Anim:   \(String(format: "%.1f", sample.currentAnimationFPS)) fps
        Uptime: \(Int(sample.uptimeSeconds)) s
        """
    }
}
