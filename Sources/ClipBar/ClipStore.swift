import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// History on disk: text + metadata in SQLite, images as PNG files (plus small thumbnails).
/// Nothing but short previews is kept in RAM; full text/images are read on demand.
@MainActor
final class ClipStore {
    var onChange: (@MainActor () -> Void)?
    let monitor = ClipboardMonitor()

    private let db: Database?
    private let imagesDir: URL
    private let thumbsDir: URL

    init() {
        let fm = FileManager.default
        let root = Config.dataDirectory
        imagesDir = root.appendingPathComponent("images", isDirectory: true)
        thumbsDir = root.appendingPathComponent("thumbs", isDirectory: true)
        for dir in [root, imagesDir, thumbsDir] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        db = Database(path: root.appendingPathComponent("clips.sqlite").path)
        db?.exec(
            """
            CREATE TABLE IF NOT EXISTS clips (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                kind INTEGER NOT NULL,
                hash TEXT NOT NULL UNIQUE,
                text TEXT,
                preview TEXT NOT NULL DEFAULT '',
                file TEXT NOT NULL DEFAULT '',
                width INTEGER NOT NULL DEFAULT 0,
                height INTEGER NOT NULL DEFAULT 0,
                bytes INTEGER NOT NULL DEFAULT 0,
                source TEXT NOT NULL DEFAULT '',
                first_at REAL NOT NULL,
                last_at REAL NOT NULL,
                copies INTEGER NOT NULL DEFAULT 1,
                pinned INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS idx_clips_order ON clips(pinned DESC, last_at DESC);
            """)

        var hasBundleID = false
        db?.run("PRAGMA table_info(clips)") {
            if Database.text($0, 1) == "source_bid" { hasBundleID = true }
        }
        if !hasBundleID {
            db?.exec("ALTER TABLE clips ADD COLUMN source_bid TEXT NOT NULL DEFAULT ''")
        }

        monitor.onText = { [weak self] text, source in self?.addText(text, source: source) }
        monitor.onImage = { [weak self] data, source in self?.addImage(data, source: source) }
        monitor.onFiles = { [weak self] urls, source in self?.addFiles(urls, source: source) }
    }

    // MARK: Reading
    /// Pinned first, then most recently used. Never loads full text into memory.
    func list(search: String) -> [Clip] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return fetch(condition: nil, binds: []) }

        switch Settings.searchMode {
        case .exact: return exactMatches(query)
        case .fuzzy: return fuzzyMatches(query)
        case .regex: return regexMatches(query)
        case .mixed:
            let a = exactMatches(query)
            if !a.isEmpty { return a }
            let b = regexMatches(query)
            if !b.isEmpty { return b }
            return fuzzyMatches(query)
        }
    }

    private func exactMatches(_ q: String) -> [Clip] {
        fetch(condition: "text LIKE ? ESCAPE '\\'", binds: [.text("%" + Self.escapeLike(q) + "%")])
    }

    /// Letters in order with anything in between: "cbr" becomes %c%b%r%.
    private func fuzzyMatches(_ q: String) -> [Clip] {
        let letters = q.filter { !$0.isWhitespace }.map { Self.escapeLike(String($0)) }
        guard !letters.isEmpty else { return [] }
        return fetch(
            condition: "text LIKE ? ESCAPE '\\'",
            binds: [.text("%" + letters.joined(separator: "%") + "%")])
    }

    /// Streams the texts one row at a time and keeps only the ids that match. An invalid pattern finds nothing.
    private func regexMatches(_ q: String) -> [Clip] {
        guard let re = try? NSRegularExpression(pattern: q, options: [.caseInsensitive]) else {
            return []
        }
        var ids: [String] = []
        db?.run("SELECT id, text FROM clips WHERE text IS NOT NULL") { s in
            let text = Database.text(s, 1)
            if re.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text))
                != nil
            {
                ids.append(String(Database.int(s, 0)))
            }
        }
        guard !ids.isEmpty else { return [] }
        return fetch(condition: "id IN (\(ids.joined(separator: ",")))", binds: [])
    }

    private func fetch(condition: String?, binds: [Bind]) -> [Clip] {
        guard let db else { return [] }
        var sql =
            "SELECT id, kind, preview, file, width, height, bytes, source, first_at, last_at, copies, pinned, source_bid FROM clips"
        if let condition { sql += " WHERE " + condition }
        sql += " ORDER BY pinned DESC, last_at DESC LIMIT ?"
        var allBinds = binds
        allBinds.append(.int(Int64(Config.listLimit)))

        var out: [Clip] = []
        db.run(sql, allBinds) { s in
            out.append(
                Clip(
                    id: Database.int(s, 0),
                    kind: Clip.Kind(rawValue: Int(Database.int(s, 1))) ?? .text,
                    preview: Database.text(s, 2),
                    file: Database.text(s, 3),
                    width: Int(Database.int(s, 4)),
                    height: Int(Database.int(s, 5)),
                    bytes: Int(Database.int(s, 6)),
                    source: Database.text(s, 7),
                    sourceBundleID: Database.text(s, 12),
                    firstAt: Date(timeIntervalSince1970: Database.real(s, 8)),
                    lastAt: Date(timeIntervalSince1970: Database.real(s, 9)),
                    copies: Int(Database.int(s, 10)),
                    pinned: Database.int(s, 11) != 0))
        }
        return out
    }

    func fullText(_ id: Int64) -> String? {
        var result: String?
        db?.run("SELECT text FROM clips WHERE id = ?", [.int(id)]) { result = Database.text($0, 0) }
        return result
    }

    func imageURL(_ clip: Clip) -> URL { imagesDir.appendingPathComponent(clip.file) }
    func thumbURL(_ clip: Clip) -> URL { thumbsDir.appendingPathComponent(clip.file) }

    func totalCount() -> Int { scalar("SELECT COUNT(*) FROM clips") }
    func unpinnedCount() -> Int { scalar("SELECT COUNT(*) FROM clips WHERE pinned = 0") }

    // MARK: Adding (called by the clipboard monitor)

    func addText(_ raw: String, source: String) {
        guard raw.utf8.count <= Config.maxTextBytes,
            raw.contains(where: { !$0.isWhitespace })
        else { return }
        let hash = Self.sha(Data(raw.utf8))
        if bump(hash: hash) { return }

        let oneLine = raw.prefix(400).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        insert(
            kind: .text, hash: hash, text: raw, preview: String(oneLine.prefix(200)),
            file: "", width: 0, height: 0, bytes: raw.utf8.count, source: source)
    }

    func addFiles(_ urls: [URL], source: String) {
        let text = urls.map(\.absoluteString).joined(separator: "\n")  // file:///… one per line
        guard !urls.isEmpty, text.utf8.count <= Config.maxTextBytes else { return }
        let hash = Self.sha(Data(("files\n" + text).utf8))
        if bump(hash: hash) { return }

        let preview = urls.map(\.path).joined(separator: ", ")
        let size = urls.reduce(0) {
            $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        insert(
            kind: .file, hash: hash, text: text, preview: String(preview.prefix(200)),
            file: "", width: 0, height: 0, bytes: size, source: source)
    }

    func addImage(_ data: Data, source: String) {
        guard data.count <= Config.maxImageBytes else { return }
        let hash = Self.sha(data)
        if bump(hash: hash) { return }

        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return }
        let size = ImageTools.pixelSize(src)
        let name = hash + ".png"
        let imageURL = imagesDir.appendingPathComponent(name)
        let thumbURL = thumbsDir.appendingPathComponent(name)

        let isPNG = (CGImageSourceGetType(src) as String?) == UTType.png.identifier
        if isPNG {
            guard (try? data.write(to: imageURL)) != nil else { return }
        } else {
            guard let full = CGImageSourceCreateImageAtIndex(src, 0, nil),
                ImageTools.writePNG(full, to: imageURL)
            else { return }
        }
        guard let thumb = ImageTools.thumbnail(src, maxPixel: Config.thumbPixels),
            ImageTools.writePNG(thumb, to: thumbURL)
        else {
            try? FileManager.default.removeItem(at: imageURL)
            return
        }
        insert(
            kind: .image, hash: hash, text: nil, preview: "", file: name,
            width: size.width, height: size.height, bytes: data.count, source: source)
    }

    // MARK: Changing

    /// Selected item: counts as a fresh copy, so it jumps back to the top (below pinned ones).
    func touch(_ id: Int64) {
        db?.run(
            "UPDATE clips SET last_at = ?, copies = copies + 1 WHERE id = ?",
            [.real(Date().timeIntervalSince1970), .int(id)])
        onChange?()
    }

    func togglePin(_ id: Int64) {
        db?.run("UPDATE clips SET pinned = 1 - pinned WHERE id = ?", [.int(id)])
        onChange?()
    }

    func delete(_ id: Int64) {
        db?.run("DELETE FROM clips WHERE id = ?", [.int(id)])
        sweepOrphans()
        onChange?()
    }

    /// Removes everything except pinned items, deletes their files and shrinks the database.
    func clearUnpinned() {
        db?.run("DELETE FROM clips WHERE pinned = 0")
        sweepOrphans()
        db?.exec("VACUUM")
        onChange?()
    }

    /// Writes the item back to the system clipboard, then moves it to the top.
    @discardableResult
    func copyToPasteboard(_ clip: Clip) -> Bool {
        let pb = NSPasteboard.general
        switch clip.kind {
        case .text:
            guard let text = fullText(clip.id) else { return false }
            pb.clearContents()
            _ = pb.setString(text, forType: .string)
        case .image:
            guard let data = try? Data(contentsOf: imageURL(clip)) else { return false }
            pb.clearContents()
            _ = pb.setData(data, forType: .png)

        case .file:
            guard let text = fullText(clip.id) else { return false }
            let urls = text.split(separator: "\n").compactMap { URL(string: String($0)) }
            guard !urls.isEmpty else { return false }
            pb.clearContents()
            pb.writeObjects(urls.map { $0 as NSURL })
        }
        monitor.ignoreCurrent()  // don't record our own write as a new copy
        touch(clip.id)
        return true
    }

    /// Deletes image/thumbnail files that no row refers to any more.
    func sweepOrphans() {
        var keep = Set<String>()
        db?.run("SELECT file FROM clips WHERE kind = 1") { keep.insert(Database.text($0, 0)) }
        let fm = FileManager.default
        for dir in [imagesDir, thumbsDir] {
            for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            where !keep.contains(name) {
                try? fm.removeItem(at: dir.appendingPathComponent(name))
            }
        }
    }

    // MARK: Internals

    /// Same content copied again: update counters instead of storing a duplicate.
    private func bump(hash: String) -> Bool {
        var exists = false
        db?.run("SELECT id FROM clips WHERE hash = ?", [.text(hash)]) { _ in exists = true }
        guard exists else { return false }
        db?.run(
            "UPDATE clips SET last_at = ?, copies = copies + 1 WHERE hash = ?",
            [.real(Date().timeIntervalSince1970), .text(hash)])
        onChange?()
        return true
    }

    private func insert(
        kind: Clip.Kind, hash: String, text: String?, preview: String, file: String,
        width: Int, height: Int, bytes: Int, source: String
    ) {
        let now = Date().timeIntervalSince1970
        db?.run(
            """
            INSERT INTO clips (kind, hash, text, preview, file, width, height, bytes, source, source_bid, first_at, last_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .int(Int64(kind.rawValue)), .text(hash), text.map(Bind.text) ?? .null,
                .text(preview),
                .text(file), .int(Int64(width)), .int(Int64(height)), .int(Int64(bytes)),
                .text(source),
                .text(monitor.sourceBundleID), .real(now), .real(now),
            ])
        prune()
        onChange?()
    }

    /// Keeps the newest `historyLimit` unpinned items.
    private func prune() {
        db?.run(
            """
            DELETE FROM clips WHERE id IN (
                SELECT id FROM clips WHERE pinned = 0 ORDER BY last_at DESC LIMIT -1 OFFSET ?)
            """, [.int(Int64(Config.historyLimit))])
        if (db?.changes ?? 0) > 0 { sweepOrphans() }
    }

    private func scalar(_ sql: String) -> Int {
        var value = 0
        db?.run(sql) { value = Int(Database.int($0, 0)) }
        return value
    }

    nonisolated private static func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func escapeLike(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
