@testable import SkilliCore
import XCTest

final class LinkPreviewTests: XCTestCase {
    private let base = URL(string: "https://www.example.com/blog/post?id=7")!

    // MARK: - The head

    func testOpenGraphTagsComeFirst() {
        let html = """
        <!doctype html>
        <html lang="en"><head>
        <meta charset="utf-8">
        <title>Plain title | Example</title>
        <meta name="description" content="The plain description.">
        <meta property="og:title" content="The Open Graph title">
        <meta property="og:description" content="What the card says &amp; more">
        <meta property="og:site_name" content="Example Blog">
        <meta property="og:image" content="/images/card.png">
        <link rel="icon" href="/favicon-32.png" sizes="32x32">
        <link rel="apple-touch-icon" href="https://cdn.example.com/touch.png">
        </head><body><meta property="og:title" content="Not in the head"></body></html>
        """
        let preview = LinkPreviews.parse(html: html, base: base)
        XCTAssertEqual(preview.title, "The Open Graph title")
        XCTAssertEqual(preview.summary, "What the card says & more")
        XCTAssertEqual(preview.siteName, "Example Blog")
        XCTAssertEqual(preview.imageURL, URL(string: "https://www.example.com/images/card.png"))
        XCTAssertEqual(preview.iconURLs, [URL(string: "https://cdn.example.com/touch.png")!,
                                          URL(string: "https://www.example.com/favicon-32.png")!,
                                          URL(string: "https://www.example.com/favicon.ico")!])
        XCTAssertFalse(preview.isEmpty)
    }

    func testTwitterCardsThenTheTitleTag() {
        let html = """
        <head>
          <TITLE>
            Café &eacute;t&#233; &#x2014; Notes
          </TITLE>
          <meta name='twitter:description' content='Short summary'>
          <meta name=twitter:image content=//images.example.org/a.jpg>
          <meta itemprop="name" content="Item name">
        </head>
        """
        let preview = LinkPreviews.parse(html: html, base: base)
        XCTAssertEqual(preview.title, "Café été — Notes", "entities decoded, spaces made one")
        XCTAssertEqual(preview.summary, "Short summary")
        XCTAssertEqual(preview.imageURL, URL(string: "https://images.example.org/a.jpg"), "protocol-relative, on the page's scheme")
        XCTAssertNil(preview.siteName)
        XCTAssertEqual(preview.iconURLs, [URL(string: "https://www.example.com/favicon.ico")!])
    }

    func testScriptsCommentsAndTheBaseTag() {
        let html = """
        <head>
        <!-- <meta property="og:title" content="In a comment"> -->
        <script>var s = '<meta property="og:title" content="In a script">';</script>
        <style>.a{content:"<title>In a style</title>"}</style>
        <base href="https://static.example.net/site/">
        <meta property="og:image" content="card.jpg">
        <meta property="og:title" content="The real title">
        </head>
        """
        let preview = LinkPreviews.parse(html: html, base: base)
        XCTAssertEqual(preview.title, "The real title")
        XCTAssertEqual(preview.imageURL, URL(string: "https://static.example.net/site/card.jpg"))
    }

    func testOnlyWebAddressesAreKept() {
        let html = """
        <head>
        <meta property="og:image" content="data:image/png;base64,AAAA">
        <meta property="og:title" content="   ">
        <link rel="icon" href="javascript:alert(1)">
        <link rel="icon" type="image/svg+xml" href="/icon.svg">
        <link rel="icon" href="/icon.png">
        </head>
        """
        let preview = LinkPreviews.parse(html: html, base: base)
        XCTAssertNil(preview.imageURL)
        XCTAssertNil(preview.title, "a blank title is none")
        XCTAssertEqual(preview.iconURLs.map(\.path), ["/icon.png", "/icon.svg", "/favicon.ico"], "SVG after the pictures every Mac draws")
        XCTAssertTrue(preview.isEmpty)
    }

    func testLongWordsAreCut() {
        let long = String(repeating: "word ", count: 200)
        let preview = LinkPreviews.parse(html: "<head><meta property=\"og:description\" content=\"\(long)\"></head>", base: base)
        XCTAssertEqual(preview.summary?.count, 600)
        XCTAssertEqual(preview.summary?.last, "…")
    }

    func testTheCharsetTheHeaderOrTheHeadSays() {
        let latin = Data("<head><title>Caf\u{E9}</title></head>".data(using: .isoLatin1)!)
        XCTAssertEqual(LinkPreviews.decode(latin, contentType: "text/html; charset=ISO-8859-1"), "<head><title>Café</title></head>")
        let declared = Data("<meta charset=\"windows-1252\"><title>\u{E9}t\u{E9}</title>".data(using: .windowsCP1252)!)
        XCTAssertTrue(LinkPreviews.decode(declared, contentType: "text/html").contains("été"))
        XCTAssertEqual(LinkPreviews.decode(Data("été".utf8), contentType: nil), "été")
        XCTAssertTrue(LinkPreviews.headEnded(Data("<html><head></head>".utf8)))
        XCTAssertFalse(LinkPreviews.headEnded(Data("<html><head><title>".utf8)))
    }

    // MARK: - What may be fetched

    func testOnlyHTTPLinksWithoutSignInsAreFetched() {
        XCTAssertTrue(LinkPreviews.isFetchable(URL(string: "https://skil.li")!))
        XCTAssertTrue(LinkPreviews.isFetchable(URL(string: "http://127.0.0.1:8080/page")!))
        XCTAssertFalse(LinkPreviews.isFetchable(URL(string: "https://me:secret@example.com")!), "a password would be sent")
        XCTAssertFalse(LinkPreviews.isFetchable(URL(string: "https://camille@example.com")!))
        XCTAssertFalse(LinkPreviews.isFetchable(URL(string: "file:///etc/hosts")!))
        XCTAssertFalse(LinkPreviews.isFetchable(URL(string: "skilli://run/cmd:emoji")!))
        XCTAssertFalse(LinkPreviews.isFetchable(URL(string: "javascript:alert(1)")!))
        XCTAssertEqual(LinkPreviews.domain(of: URL(string: "https://www.github.com/nomdelasociete")!), "github.com")
    }

    // MARK: - Kept with the copy

    func testWhenAPageIsReadAgain() {
        let url = URL(string: "https://skil.li")!
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        XCTAssertTrue(LinkPreviewCache.needsFetch(nil, for: url, now: now), "never read")
        let found = LinkPreviewRecord(url: url, fetched: now.addingTimeInterval(-3_600), outcome: .found, preview: LinkPreview(title: "skil.li"))
        XCTAssertFalse(LinkPreviewCache.needsFetch(found, for: url, now: now), "read an hour ago")
        XCTAssertTrue(LinkPreviewCache.needsFetch(found, for: url, now: now.addingTimeInterval(7 * 86_400)), "a week later")
        XCTAssertTrue(LinkPreviewCache.needsFetch(found, for: URL(string: "https://apple.com")!, now: now), "another link")
        let failed = LinkPreviewRecord(url: url, fetched: now.addingTimeInterval(-60), outcome: .failed)
        XCTAssertFalse(LinkPreviewCache.needsFetch(failed, for: url, now: now), "failed a minute ago")
        XCTAssertTrue(LinkPreviewCache.needsFetch(failed, for: url, now: now.addingTimeInterval(10 * 60)), "ten minutes later")
        XCTAssertTrue(LinkPreviewCache.needsFetch(found, for: url, now: now.addingTimeInterval(-7_200)), "the clock put back")
    }

    func testFilesGoWithTheirCopy() {
        XCTAssertEqual(LinkPreviewCache.files(of: 42), ["42.json", "42.image.jpg", "42.icon.png"])
        XCTAssertEqual(LinkPreviewCache.id(ofFile: "42.json"), 42)
        XCTAssertEqual(LinkPreviewCache.id(ofFile: "42.image.jpg"), 42)
        XCTAssertNil(LinkPreviewCache.id(ofFile: "42.txt"))
        XCTAssertNil(LinkPreviewCache.id(ofFile: ".DS_Store"))
        XCTAssertNil(LinkPreviewCache.id(ofFile: "notes.json"))
        let names = ["1.json", "1.image.jpg", "2.json", "2.icon.png", "3.json", ".DS_Store", "other.png"]
        XCTAssertEqual(LinkPreviewCache.orphans(among: names, kept: [1, 3]), ["2.json", "2.icon.png"])
    }

    func testARecordReadsBack() throws {
        let record = LinkPreviewRecord(url: URL(string: "https://skil.li")!, fetched: Date(timeIntervalSince1970: 1_000), outcome: .found,
                                       preview: LinkPreview(title: "skil.li", summary: "Fast", siteName: nil,
                                                            imageURL: URL(string: "https://skil.li/card.png"),
                                                            iconURLs: [URL(string: "https://skil.li/favicon.ico")!]),
                                       image: "7.image.jpg", icon: nil)
        let data = try JSONEncoder().encode(record)
        XCTAssertEqual(try JSONDecoder().decode(LinkPreviewRecord.self, from: data), record)
    }
}
