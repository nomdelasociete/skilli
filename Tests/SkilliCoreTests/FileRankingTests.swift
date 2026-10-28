import XCTest
@testable import SkilliCore

final class FileRankingTests: XCTestCase {
    let home = "/Users/me"

    func testWhatIsLeftOut() {
        func exclusion(_ relative: String) -> FileRanking.Exclusion? { FileRanking.exclusion(of: "\(home)/\(relative)", home: home) }
        XCTAssertNil(exclusion("Documents/Admin/Contrat.pdf"))
        XCTAssertNil(exclusion("Projects/site/README.md"))
        XCTAssertNil(exclusion("Library/CloudStorage/GoogleDrive-me@example.com/My Drive/Facture.pdf"))
        XCTAssertNil(exclusion("Library/Mobile Documents/com~apple~CloudDocs/Admin/Bail.pdf"))
        XCTAssertNil(exclusion("Applications/Notes.app"), "the app itself, not what is inside")
        XCTAssertEqual(exclusion("Library/Caches/logo.png"), .outside)
        XCTAssertEqual(FileRanking.exclusion(of: "/opt/homebrew/README.md", home: home), .outside)
        XCTAssertEqual(exclusion("Projects/site/node_modules/react/README.md"), .dependency)
        XCTAssertEqual(exclusion("Projects/app/Pods/Alamofire/README.md"), .dependency)
        XCTAssertEqual(exclusion("Projects/tool/venv/lib/python3.12/site-packages/x/README.md"), .dependency)
        XCTAssertEqual(exclusion("go/pkg/mod/github.com/user/repo@v1.0.0/README.md"), .dependency)
        XCTAssertEqual(exclusion("Projects/.claude/worktrees/x/README.md"), .hidden)
        XCTAssertEqual(exclusion(".config/app/config.json"), .hidden)
        XCTAssertEqual(exclusion("Applications/Notes.app/Contents/Resources/logo.png"), .package)
        XCTAssertEqual(exclusion("Pictures/Photos Library.photoslibrary/originals/A/IMG_1.jpg"), .package)
        XCTAssertEqual(exclusion("Projects/App/Assets.xcassets/Logo.imageset/logo.png"), .package)
        XCTAssertNil(exclusion("Documents/node_modules.txt"), "a name, not a folder")
    }

    func testBuildOutput() {
        let root = "\(home)/Projects/site"
        XCTAssertTrue(FileRanking.isBuildOutput("\(root)/dist/logo.png", projectRoot: root))
        XCTAssertTrue(FileRanking.isBuildOutput("\(root)/packages/web/build/static/logo.png", projectRoot: root))
        XCTAssertFalse(FileRanking.isBuildOutput("\(root)/src/logo.png", projectRoot: root))
        XCTAssertFalse(FileRanking.isBuildOutput("\(root)/build.sh", projectRoot: root), "a file named build")
        XCTAssertFalse(FileRanking.isBuildOutput("\(home)/Documents/build/plan.pdf", projectRoot: root))
    }

    func testCodeQuery() {
        XCTAssertTrue(FileRanking.isCodeQuery("config.ts"))
        XCTAssertTrue(FileRanking.isCodeQuery("main .swift"), "the extension alone")
        XCTAssertFalse(FileRanking.isCodeQuery("config"))
        XCTAssertFalse(FileRanking.isCodeQuery("facture edf"))
        XCTAssertFalse(FileRanking.isCodeQuery("v1."))
        XCTAssertFalse(FileRanking.isCodeQuery("Capture d’écran 2026-10-10 à 14.32.11"), "a time's dots")
    }

    func testFolderWords() {
        let words = FileRanking.words("martin invoice")
        XCTAssertTrue(FileRanking.matchesFolderWords(words, name: "Invoice.pdf", folder: "Clients/Margot Martin"))
        XCTAssertFalse(FileRanking.matchesFolderWords(words, name: "Notes.txt", folder: "Clients/Margot Martin/Invoices"),
                       "one word at least in the name")
        XCTAssertTrue(FileRanking.matchesFolderWords(FileRanking.words("électricité"), name: "Facture-electricite.pdf", folder: ""))
    }

    func testMatchOrder() {
        let words = FileRanking.words("logo")
        XCTAssertEqual(FileRanking.matchScore(name: "Logo.png", words: words), 60)
        XCTAssertEqual(FileRanking.matchScore(name: "logo-final.ai", words: words), 45)
        XCTAssertEqual(FileRanking.matchScore(name: "brand-logo.svg", words: words), 30)
        XCTAssertEqual(FileRanking.matchScore(name: "BrandLogo.svg", words: words), 30, "a capital starts a word")
        XCTAssertEqual(FileRanking.matchScore(name: "catalogo.pdf", words: words), 15)
        XCTAssertEqual(FileRanking.matchScore(name: "Invoice.pdf", words: FileRanking.words("martin invoice")), 5)
        XCTAssertEqual(FileRanking.matchScore(name: "aws-invoices-2026", words: FileRanking.words("2026 invoice")), 30)
    }

    func testWordStarts() {
        XCTAssertTrue(FileRanking.startsWord("invoice", in: "aws-invoices-2026"))
        XCTAssertTrue(FileRanking.startsWord("invoice", in: "AwsInvoices"))
        XCTAssertTrue(FileRanking.startsWord("electricite", in: "Facture-Électricité.pdf"), "accents folded")
        XCTAssertFalse(FileRanking.startsWord("invoice", in: "preinvoice.pdf"))
        XCTAssertFalse(FileRanking.startsWord("longer than the name", in: "a.pdf"))
        XCTAssertTrue(FileRanking.startsWord("plan", in: "Straße-Plan.pdf"))
        XCTAssertTrue(FileRanking.startsWord("report", in: "\u{FB01}le-report.pdf"), "a ligature, however it folds")
    }

    /// Files the user opened first; in a project, its code and what nobody
    /// changed for a month behind; an extension typed wants code.
    func testUsersFilesFirst() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let days = { (count: Double) in now.addingTimeInterval(-count * 86_400) }
        func score(_ name: String, used: Date? = nil, modified: Double = 3, inProject: Bool, query: String) -> Int {
            FileRanking.score(name: name, folder: "", words: FileRanking.words(query), used: used, modified: days(modified), inProject: inProject,
                              codeQuery: FileRanking.isCodeQuery(query), now: now)!
        }
        let cloned = score("README.md", modified: 200, inProject: true, query: "readme")
        let written = score("README.md", modified: 1, inProject: true, query: "readme")
        let mine = score("Readme notes.txt", used: days(20), inProject: false, query: "readme")
        XCTAssertGreaterThan(written, cloned)
        XCTAssertGreaterThan(mine, cloned)
        XCTAssertGreaterThan(score("README.md", used: days(1), inProject: true, query: "readme"), mine)
        XCTAssertGreaterThan(score("logo.png", inProject: true, query: "logo"), score("logo.tsx", inProject: true, query: "logo"))
        XCTAssertEqual(score("logo.png", inProject: true, query: "logo"), score("logo.png", inProject: false, query: "logo"))
        XCTAssertEqual(score("config.ts", inProject: true, query: "config.ts"), score("config.ts", inProject: false, query: "config.ts"),
                       "an extension typed: code wanted")
        XCTAssertNil(FileRanking.score(name: "Notes.txt", folder: "", words: FileRanking.words("readme"), used: nil, modified: nil,
                                       inProject: false, codeQuery: false))
    }

    func testCloudFolders() {
        XCTAssertEqual(FileMeaning.folder(of: "\(home)/Library/CloudStorage/GoogleDrive-me@example.com/My Drive/Admin/x.pdf", home: home),
                       "Google Drive/My Drive/Admin")
        XCTAssertEqual(FileMeaning.folder(of: "\(home)/Library/CloudStorage/Dropbox/x.pdf", home: home), "Dropbox")
        XCTAssertEqual(FileMeaning.folder(of: "\(home)/Library/Mobile Documents/com~apple~CloudDocs/Admin/x.pdf", home: home), "iCloud Drive/Admin")
        XCTAssertEqual(FileMeaning.folder(of: "\(home)/Library/Mobile Documents/com~apple~CloudDocs/x.pdf", home: home), "iCloud Drive")
        XCTAssertEqual(FileMeaning.folder(of: "\(home)/Library/Mobile Documents/iCloud~md~obsidian/Documents/x.md", home: home),
                       "iCloud Drive/obsidian/Documents")
        XCTAssertEqual(FileMeaning.folder(of: "\(home)/Library/Caches/x", home: home), "Library/Caches")
    }
}
