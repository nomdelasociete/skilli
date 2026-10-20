import Foundation

/// Ready quicklinks the user adds one by one (Settings → Catalog →
/// Quicklinks → Add from Library…): never all of them by default. Each
/// with a keyword that clashes with no shipped quicklink, no launcher
/// prefix and no word its parsers read.
public enum QuicklinkLibrary {
    public enum Group: String, CaseIterable, Sendable {
        case search, words, developers, everyday

        public var title: String {
            switch self {
            case .search: "Search"
            case .words: "Words & Translation"
            case .developers: "Developers"
            case .everyday: "Shopping & More"
            }
        }
    }

    public struct Item: Identifiable, Sendable {
        public let name: String
        public let keyword: String
        public let url: String
        public let group: Group

        public var id: String { url }

        init(_ name: String, _ keyword: String, _ url: String, _ group: Group) {
            self.name = name
            self.keyword = keyword
            self.url = url
            self.group = group
        }
    }

    public static let items: [Item] = [
        Item("Google Maps", "gm", "https://www.google.com/maps/search/?api=1&query={query}", .search),
        Item("Google Images", "gi", "https://www.google.com/search?tbm=isch&q={query}", .search),
        Item("DuckDuckGo", "ddg", "https://duckduckgo.com/?q={query}", .search),
        Item("Wikipedia (English)", "wen", "https://en.wikipedia.org/w/index.php?search={query}", .search),
        Item("Wikipedia (French)", "wfr", "https://fr.wikipedia.org/w/index.php?search={query}", .search),
        Item("Reddit", "reddit", "https://www.reddit.com/search/?q={query}", .search),

        Item("DeepL (French → English)", "dl", "https://www.deepl.com/translator#fr/en/{query}", .words),
        Item("DeepL (English → French)", "dlf", "https://www.deepl.com/translator#en/fr/{query}", .words),
        Item("WordReference (English → French)", "wrf", "https://www.wordreference.com/enfr/{query}", .words),
        Item("WordReference (French → English)", "wre", "https://www.wordreference.com/fren/{query}", .words),
        Item("Larousse", "lar", "https://www.larousse.fr/dictionnaires/francais/{query}", .words),

        Item("MDN Web Docs", "mdn", "https://developer.mozilla.org/en-US/search?q={query}", .developers),
        Item("Apple Developer", "adev", "https://developer.apple.com/search/?q={query}", .developers),
        Item("Stack Overflow", "so", "https://stackoverflow.com/search?q={query}", .developers),
        Item("npm", "npm", "https://www.npmjs.com/search?q={query}", .developers),
        Item("Swift Package Index", "spi", "https://swiftpackageindex.com/search?query={query}", .developers),
        Item("PyPI", "pypi", "https://pypi.org/search/?q={query}", .developers),
        Item("crates.io", "crates", "https://crates.io/search?q={query}", .developers),

        Item("Amazon.fr", "amz", "https://www.amazon.fr/s?k={query}", .everyday),
        Item("Leboncoin", "lbc", "https://www.leboncoin.fr/recherche?text={query}", .everyday),
        Item("IMDb", "imdb", "https://www.imdb.com/find/?q={query}", .everyday),
        Item("Spotify", "spot", "https://open.spotify.com/search/{query}", .everyday),
        Item("Annuaire des Entreprises", "siren", "https://annuaire-entreprises.data.gouv.fr/rechercher?terme={query}", .everyday)
    ]

    /// The library by group, in `Group`'s order.
    public static var groups: [(group: Group, items: [Item])] {
        Group.allCases.map { group in (group, items.filter { $0.group == group }) }
    }

    /// Already among `links`: the same address (case aside).
    public static func isAdded(_ item: Item, in links: [Quicklink]) -> Bool {
        links.contains { $0.url.lowercased() == item.url.lowercased() }
    }

    /// The quicklink `item` adds: its keyword, unless one of `links` has it
    /// already (then found by name only, and a keyword can be given).
    public static func quicklink(for item: Item, among links: [Quicklink]) -> Quicklink {
        let taken = links.contains { $0.keyword.lowercased() == item.keyword.lowercased() }
        return Quicklink(name: item.name, keyword: taken ? "" : item.keyword, url: item.url)
    }
}
