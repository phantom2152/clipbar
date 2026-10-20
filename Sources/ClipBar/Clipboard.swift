import AppKit

/// Polls the pasteboard change counter (macOS has no change notification).
/// The poll itself is a single integer compare, so it costs almost nothing.
@MainActor
final class ClipboardMonitor {
    var onText: (@MainActor (_ text: String, _ source: String) -> Void)?
    var onImage: (@MainActor (_ data: Data, _ source: String) -> Void)?
    var onFiles: (@MainActor (_ urls: [URL], _ source: String) -> Void)?

    private var lastCount = -1  // -1: the clipboard content at launch is captured too
    private var timer: Timer?
    private(set) var sourceBundleID = ""

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        t.tolerance = 0.25
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Call right after ClipBar itself writes to the pasteboard.
    func ignoreCurrent() { lastCount = NSPasteboard.general.changeCount }

    private func poll() {
        let pb = NSPasteboard.general
        let count = pb.changeCount
        guard count != lastCount else { return }
        lastCount = count

        // Password managers mark secrets as concealed/transient: never record those.
        // (Delete this check if you want everything saved.)
        let skip: Set<String> = [
            "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
        ]
        if let types = pb.types, types.contains(where: { skip.contains($0.rawValue) }) { return }

        let front = NSWorkspace.shared.frontmostApplication
        let source = front?.localizedName ?? ""
        sourceBundleID = front?.bundleIdentifier ?? ""

        if let urls = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty
        {
            onFiles?(urls, source)
        } else if let text = pb.string(forType: .string) {
            onText?(text, source)
        } else if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
            onImage?(data, source)
        }
    }
}
