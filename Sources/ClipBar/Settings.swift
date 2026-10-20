import Foundation

enum SearchMode: String, CaseIterable {
    case exact, fuzzy, regex, mixed

    var title: String {
        switch self {
        case .exact: "Exact"
        case .fuzzy: "Fuzzy"
        case .regex: "Regex"
        case .mixed: "Mixed"
        }
    }

    var help: String {
        switch self {
        case .exact: "Finds your text anywhere in the item."
        case .fuzzy:
            "Letters must appear in order but not next to each other (\"cbr\" finds \"ClipBar\")."
        case .regex: "Your search is a regular expression, for example ^https?://"
        case .mixed:
            "Tries exact first, then regex, then fuzzy. Shows the first one that finds something."
        }
    }
}

/// User settings, stored in UserDefaults. Later tabs add their own keys here.
enum Settings {
    static var searchMode: SearchMode {
        get {
            SearchMode(rawValue: UserDefaults.standard.string(forKey: "searchMode") ?? "") ?? .exact
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "searchMode") }
    }

    /// Ask before "Clear". On by default.
    static var confirmClear: Bool {
        get { UserDefaults.standard.object(forKey: "confirmClear") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "confirmClear") }
    }

    /// Remove unpinned history when the app quits. Off by default.
    static var clearOnQuit: Bool {
        get { UserDefaults.standard.bool(forKey: "clearOnQuit") }
        set { UserDefaults.standard.set(newValue, forKey: "clearOnQuit") }
    }

    /// Show ⏎ ⇥ · for invisible characters in list rows. On by default.
    static var showSpecialSymbols: Bool {
        get { UserDefaults.standard.object(forKey: "showSpecialSymbols") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showSpecialSymbols") }
    }

    /// Color dot / swatch for items that are hex colors. On by default.
    static var showHexSwatch: Bool {
        get { UserDefaults.standard.object(forKey: "showHexSwatch") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showHexSwatch") }
    }

    /// Most unpinned items kept (older ones are removed). Pinned items never count.
    static var maxItems: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: "maxItems")
            return v > 0 ? v : 200
        }
        set { UserDefaults.standard.set(newValue, forKey: "maxItems") }
    }

    /// Total size of unpinned items in MB. 0 = no limit.
    static var maxSizeMB: Int {
        get { UserDefaults.standard.object(forKey: "maxSizeMB") as? Int ?? 500 }
        set { UserDefaults.standard.set(newValue, forKey: "maxSizeMB") }
    }

    static var storeText: Bool {
        get { UserDefaults.standard.object(forKey: "storeText") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "storeText") }
    }
    static var storeImages: Bool {
        get { UserDefaults.standard.object(forKey: "storeImages") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "storeImages") }
    }
    static var storeFiles: Bool {
        get { UserDefaults.standard.object(forKey: "storeFiles") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "storeFiles") }
    }

    /// Pasteboard types ignored out of the box: password managers mark their secrets with these.
    static let defaultIgnoredTypes = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "de.petermaurer.TransientPasteboardType",
        "com.typeit4me.clipping",
        "Pasteboard generator type",
        "com.agilebits.onepassword",
        "net.antelle.keeweb",
    ]

    /// Bundle ids of apps whose copies are never stored.
    static var ignoredApps: [String] {
        get { UserDefaults.standard.stringArray(forKey: "ignoredApps") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "ignoredApps") }
    }

    static var ignoredTypes: [String] {
        get { UserDefaults.standard.stringArray(forKey: "ignoredTypes") ?? defaultIgnoredTypes }
        set { UserDefaults.standard.set(newValue, forKey: "ignoredTypes") }
    }

    /// Text copies matching any of these patterns are never stored.
    static var ignoredRegex: [String] {
        get { UserDefaults.standard.stringArray(forKey: "ignoredRegex") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "ignoredRegex") }
    }
}
