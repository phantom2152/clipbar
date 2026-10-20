import Foundation

/// Fixed paths and limits.
enum Config {
    static let historyLimit = 200            // unpinned items kept; pinned items are never pruned
    static let listLimit = 200               // rows shown at once
    static let maxTextBytes = 5_000_000      // bigger text copies are ignored
    static let maxImageBytes = 30_000_000    // bigger image copies are ignored
    static let thumbPixels = 200             // list thumbnails (stored on disk)
    static let previewPixels = 600           // side-panel image (decoded on demand, never stored)

    /// ~/Library/Application Support/ClipBar  (clips.sqlite, images/, thumbs/)
    static var dataDirectory: URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
        return base.appendingPathComponent("ClipBar", isDirectory: true)
    }
}
