import Foundation

/// Metadata of one history item. Full text and full images are NOT held here:
/// they are read from disk only when previewed or pasted.
struct Clip: Identifiable, Equatable, Sendable {
    enum Kind: Int, Sendable {
        case text = 0
        case image = 1
        case file = 2
    }

    let id: Int64
    let kind: Kind
    let preview: String  // one-line text, first ~200 characters
    let file: String  // image file name (same name in images/ and thumbs/), "" for text
    let width: Int
    let height: Int
    let bytes: Int
    let source: String  // app it was copied from
    let sourceBundleID: String
    let firstAt: Date
    let lastAt: Date
    let copies: Int
    let pinned: Bool
    let title: String  // custom name for a pinned item ("" = show the text)
    let pinKey: String  // custom ⌘ key for a pinned item ("" = none)
}
