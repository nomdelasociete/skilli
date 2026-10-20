@testable import SkilliCore
import XCTest

final class GIFSearchTests: XCTestCase {
    /// Klipy's answer as its docs show it (trimmed): every size and format.
    private static func item(_ slug: String, title: String = "Hello", type: String = "gif", sizes: [String] = ["hd", "md", "sm", "xs"]) -> [String: Any] {
        var file: [String: Any] = [:]
        for size in sizes {
            var formats: [String: Any] = [:]
            for kind in ["gif", "webp", "jpg", "mp4"] {
                formats[kind] = ["url": "https://static.klipy.com/ii/\(slug)/\(size).\(kind)", "width": size == "hd" ? 498 : 220,
                                 "height": size == "hd" ? 400 : 180, "size": size == "hd" ? 4_001_918 : 1000]
            }
            file[size] = formats
        }
        return ["id": 8_041_071_659_142_944, "slug": slug, "title": title, "file": file, "tags": [], "type": type]
    }

    private static func page(_ items: [[String: Any]], hasNext: Bool = true, result: Bool = true) -> Data {
        try! JSONSerialization.data(withJSONObject: ["result": result, "data": ["data": items, "current_page": 1, "per_page": 48, "has_next": hasNext]])
    }

    func testParsesKlipysShapeInItsOrder() throws {
        let page = try Klipy.parse(Self.page([Self.item("hello-hi-662"), Self.item("bye-1", title: "  Bye  ")]))
        XCTAssertEqual(page.gifs.map(\.slug), ["hello-hi-662", "bye-1"])
        XCTAssertTrue(page.hasNext)
        let first = try XCTUnwrap(page.gifs.first)
        XCTAssertEqual(first.full.absoluteString, "https://static.klipy.com/ii/hello-hi-662/hd.gif")
        XCTAssertEqual(first.preview.absoluteString, "https://static.klipy.com/ii/hello-hi-662/md.webp")
        XCTAssertEqual(first.still.absoluteString, "https://static.klipy.com/ii/hello-hi-662/md.jpg")
        XCTAssertEqual(first.width, 498)
        XCTAssertEqual(first.height, 400)
        XCTAssertEqual(first.size, 4_001_918)
        XCTAssertEqual(page.gifs[1].title, "Bye")
    }

    /// A GIF without its hd falls back to md, then sm; an ad or an item
    /// with no GIF is not a GIF to show.
    func testFallsBackAndSkipsWhatIsNoGIF() throws {
        let page = try Klipy.parse(Self.page([Self.item("small", sizes: ["sm"]), Self.item("ad", type: "ad"), ["slug": "empty", "type": "gif"]],
                                             hasNext: false))
        XCTAssertEqual(page.gifs.map(\.slug), ["small"])
        XCTAssertEqual(page.gifs.first?.full.absoluteString, "https://static.klipy.com/ii/small/sm.gif")
        XCTAssertEqual(page.gifs.first?.preview.absoluteString, "https://static.klipy.com/ii/small/sm.webp")
        XCTAssertEqual(page.gifs.first?.still.absoluteString, "https://static.klipy.com/ii/small/sm.jpg")
        XCTAssertFalse(page.hasNext)
    }

    func testRefusesWhatIsNotKlipys() {
        XCTAssertThrowsError(try Klipy.parse(Data("<html>".utf8)))
        XCTAssertThrowsError(try Klipy.parse(Self.page([], result: false)))
    }

    func testURLsPutTheKeyInThePathAndKeepTheWords() throws {
        let search = try XCTUnwrap(Klipy.searchURL("chat qui danse & co", key: "abc123", page: 2, customerID: "id-1", locale: "fr"))
        let parts = try XCTUnwrap(URLComponents(url: search, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.host, "api.klipy.com")
        XCTAssertEqual(parts.path, "/api/v1/abc123/gifs/search")
        let query = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["q"], "chat qui danse & co")
        XCTAssertEqual(query["page"], "2")
        XCTAssertEqual(query["per_page"], String(Klipy.pageSize))
        XCTAssertEqual(query["customer_id"], "id-1")
        XCTAssertEqual(query["locale"], "fr")
        XCTAssertEqual(query["content_filter"], Klipy.contentFilter)
        let plus = try XCTUnwrap(Klipy.searchURL("c++ = fun?", key: "k", customerID: "c", locale: nil))
        XCTAssertTrue(plus.absoluteString.contains("q=c%2B%2B%20%3D%20fun%3F"), plus.absoluteString)

        let local = try XCTUnwrap(URL(string: "http://127.0.0.1:8123"))
        XCTAssertEqual(Klipy.trendingURL(key: "k", customerID: "c", locale: nil, base: local)?.absoluteString.hasPrefix("http://127.0.0.1:8123/api/v1/k/gifs/trending?"), true)
        XCTAssertEqual(Klipy.itemsURL(["a", "b"], key: "k", base: local)?.absoluteString, "http://127.0.0.1:8123/api/v1/k/gifs/items?slugs=a,b")
        XCTAssertEqual(Klipy.shareURL("hello-hi-662", key: "k", base: local)?.absoluteString, "http://127.0.0.1:8123/api/v1/k/gifs/share/hello-hi-662")
        // No key, no request.
        XCTAssertNil(Klipy.searchURL("cat", key: "  ", customerID: "c", locale: nil))
        // A key cannot change the path.
        XCTAssertNil(Klipy.itemsURL(["a"], key: "k/../x", base: local))
    }

    func testShareSaysWhoAndTheWords() throws {
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: Klipy.shareBody(customerID: "id-1", query: "bravo")) as? [String: String])
        XCTAssertEqual(body, ["customer_id": "id-1", "q": "bravo"])
    }

    func testLocaleIsTheCountry() {
        XCTAssertEqual(Klipy.locale(region: "FR"), "fr")
        XCTAssertNil(Klipy.locale(region: "419"))
        XCTAssertNil(Klipy.locale(region: nil))
    }

    func testRecentsNewestFirstOnceAndCapped() {
        var recents = GIFRecents()
        recents.used(.klipy("a"))
        recents.used(.file("/tmp/x.gif"))
        recents.used(.klipy("a"))
        XCTAssertEqual(recents.entries, [.klipy("a"), .file("/tmp/x.gif")])
        for index in 0..<40 { recents.used(.klipy("g\(index)")) }
        XCTAssertEqual(recents.entries.count, GIFRecents.limit)
        XCTAssertEqual(recents.entries.first, .klipy("g39"))
        recents.remove(.klipy("g39"))
        XCTAssertEqual(recents.entries.first, .klipy("g38"))
        let decoded = try? JSONDecoder().decode(GIFRecents.self, from: JSONEncoder().encode(recents))
        XCTAssertEqual(decoded, recents)
    }

    /// Recently Used's order, Klipy's read back by slug, files still there.
    func testRecentsResolveInTheirOrder() throws {
        let page = try Klipy.parse(Self.page([Self.item("b"), Self.item("a")]))
        let recents = GIFRecents(entries: [.klipy("a"), .file("/gone.gif"), .file("/here.gif"), .klipy("gone"), .klipy("b")])
        XCTAssertEqual(recents.slugs, ["a", "gone", "b"])
        let rows = recents.resolve(klipy: page.gifs) { $0 == "/here.gif" }
        XCTAssertEqual(rows.map(\.title), ["Hello", "here", "Hello"])
        XCTAssertEqual(rows.map(\.recent), [.klipy("a"), .file("/here.gif"), .klipy("b")])
    }

    /// Real Klipy (2026-10-19): a search's slugs end with the search's mark,
    /// `gifs/items` answers the plain slug. Recently Used keeps the plain one
    /// and finds it again; the share keeps the slug as given.
    func testSearchMarkedSlugsComeBackPlain() throws {
        let searched = try Klipy.parse(Self.page([Self.item("bonjour-bonjour-mon-amour-3--kULSAXj24"), Self.item("hello-3")]))
        XCTAssertEqual(searched.gifs.map(\.plainSlug), ["bonjour-bonjour-mon-amour-3", "hello-3"])
        XCTAssertEqual(searched.gifs.first?.slug, "bonjour-bonjour-mon-amour-3--kULSAXj24")
        XCTAssertEqual(KlipyGIF.plain("a--b-c"), "a--b-c", "a mark is letters and digits only")
        XCTAssertEqual(KlipyGIF.plain("--abc"), "--abc")
        var recents = GIFRecents()
        recents.used(GIF.klipy(searched.gifs[0]).recent)
        // The same GIF found by another search: once.
        let again = try Klipy.parse(Self.page([Self.item("bonjour-bonjour-mon-amour-3--Zz9")]))
        recents.used(GIF.klipy(again.gifs[0]).recent)
        XCTAssertEqual(recents.slugs, ["bonjour-bonjour-mon-amour-3"])
        // Read back as `gifs/items` answers it.
        let items = try Klipy.parse(Self.page([Self.item("bonjour-bonjour-mon-amour-3", title: "Bonjour")]))
        XCTAssertEqual(recents.resolve(klipy: items.gifs) { _ in false }.map(\.title), ["Bonjour"])
        // A slug kept with its mark (before this) is still found.
        let old = GIFRecents(entries: [.klipy("bonjour-bonjour-mon-amour-3--kULSAXj24")])
        XCTAssertEqual(old.resolve(klipy: items.gifs) { _ in false }.count, 1)
    }

    func testMarkdownWhereAFileCannotGo() throws {
        let gif = try XCTUnwrap(Klipy.parse(Self.page([Self.item("hello", title: "Hello [world]")])).gifs.first)
        XCTAssertEqual(gif.markdown, "![Hello (world)](https://static.klipy.com/ii/hello/hd.gif)")
        let editors: Set<String> = ["com.microsoft.VSCode"]
        XCTAssertEqual(GIFPaste.style(for: .klipy(gif), frontApp: "com.apple.Terminal", editors: editors), .markdown)
        XCTAssertEqual(GIFPaste.style(for: .klipy(gif), frontApp: "com.microsoft.VSCode", editors: editors), .markdown)
        XCTAssertEqual(GIFPaste.style(for: .klipy(gif), frontApp: "com.tinyspeck.slackmacgap", editors: editors), .file)
        XCTAssertEqual(GIFPaste.style(for: .klipy(gif), frontApp: nil, editors: editors), .file)
        XCTAssertEqual(GIFPaste.style(for: .file(URL(fileURLWithPath: "/x.gif")), frontApp: "com.apple.Terminal", editors: editors), .file)
    }

    func testModeOpensFromItsPrefix() {
        XCTAssertEqual(LauncherPrefix.mode(of: "gif bravo")?.command, .searchGIFs)
        XCTAssertEqual(LauncherPrefix.mode(of: "gifs bravo")?.rest, "bravo")
        XCTAssertNil(LauncherPrefix.mode(of: "gift"))
    }
}
