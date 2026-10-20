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
}
