@testable import SkilliCore
import XCTest

/// `docs/FEATURES.md` lists everything skil.li does (2026-10-16: "a file
/// in the repo with all the features, sorted, well organised"): one
/// section per Settings pane, in the sidebar's order (`<!-- pane: id -->`),
/// every Catalog entry by its title in bold, every setting and search row
/// by its name in its pane's section. A feature built without it fails
/// here.
final class FeaturesDocTests: XCTestCase {
    /// As Markdown shows it: a line wrapped in the file reads as one.
    private static let doc: String = {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = (try? String(contentsOf: root.appendingPathComponent("docs/FEATURES.md"), encoding: .utf8)) ?? ""
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }()

    /// The sections, in the file's order, by the pane id their marker names.
    private static let sections: [(pane: String, text: String)] = {
        doc.components(separatedBy: "<!-- pane: ").dropFirst().compactMap { part in
            guard let end = part.range(of: " -->") else { return nil }
            return (String(part[..<end.lowerBound]), String(part[end.upperBound...]))
        }
    }()

    private func section(_ pane: String) -> String? {
        Self.sections.first { $0.pane == pane }?.text
    }

    func testEveryPaneHasOneSectionInTheSidebarsOrder() {
        XCTAssertFalse(Self.doc.isEmpty, "docs/FEATURES.md could not be read")
        let panes = Self.sections.map(\.pane).filter { SettingsTable.panes.contains($0) }
        XCTAssertEqual(panes, SettingsTable.panes, "one section per pane (<!-- pane: id -->), in the sidebar's order")
    }

    func testEveryCatalogEntryIsListed() {
        let missing = FeatureCatalog.entries().map(\.title).filter { !Self.doc.contains("**\($0)**") }
        XCTAssertEqual(missing, [], "docs/FEATURES.md: add each, in bold, in the section it belongs to")
    }

    func testEverySettingIsInItsPanesSection() {
        let named = SettingsTable.entries.map { ($0.pane, $0.name) } + SettingsSearch.rows.map { ($0.pane, $0.title) }
        let missing = named.filter { pane, name in
            section(pane)?.localizedCaseInsensitiveContains(name) != true
        }.map { "\($0.0): \($0.1)" }
        XCTAssertEqual(missing, [], "docs/FEATURES.md: name each in its pane's section")
    }
}
