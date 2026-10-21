import XCTest
@testable import SkilliCore

final class EditorProjectTests: XCTestCase {
    func testVSCodeRecentKeepsLocalFoldersAndWorkspaces() {
        let json = """
        {"entries":[
          {"folderUri":"file:///Users/me/Documents/Github/skilli"},
          {"fileUri":"file:///Users/me/notes.md"},
          {"workspace":{"id":"abc","configPath":"file:///Users/me/Work/Nimbus%20App.code-workspace"}},
          {"folderUri":"vscode-remote://ssh-remote%2Bbox/home/me/app","remoteAuthority":"ssh-remote+box"},
          {"folderUri":"file:///Users/me/My%20Project","label":"x"}
        ]}
        """
        let found = EditorProjectParsing.vscodeRecent(Data(json.utf8))
        XCTAssertEqual(found.map(\.path), ["/Users/me/Documents/Github/skilli", "/Users/me/Work/Nimbus App.code-workspace", "/Users/me/My Project"])
        XCTAssertEqual(found.map(\.kind), [.folder, .workspace, .folder])
        XCTAssertTrue(EditorProjectParsing.vscodeRecent(Data("not json".utf8)).isEmpty)
    }

    func testZedSublimeAndJetBrains() {
        XCTAssertEqual(EditorProjectParsing.zedPaths("/Users/me/a\n/Users/me/b"), "/Users/me/a")
        XCTAssertNil(EditorProjectParsing.zedPaths(""))
        XCTAssertEqual(EditorProjectParsing.sublimeFolders(Data(#"{"folder_history":["/Users/me/site","relative"]}"#.utf8)), ["/Users/me/site"])
        let xml = """
        <application>
          <component name="RecentProjectsManager">
            <option name="additionalInfo">
              <map>
                <entry key="$USER_HOME$/IdeaProjects/old">
                  <value><RecentProjectMetaInfo><option name="projectOpenTimestamp" value="1700000000000" /></RecentProjectMetaInfo></value>
                </entry>
                <entry key="$USER_HOME$/IdeaProjects/api">
                  <value><RecentProjectMetaInfo frameTitle="api"><option name="projectOpenTimestamp" value="1760000000000" /></RecentProjectMetaInfo></value>
                </entry>
              </map>
            </option>
          </component>
        </application>
        """
        let jetBrains = EditorProjectParsing.jetBrainsRecent(xml, home: "/Users/me")
        XCTAssertEqual(jetBrains.map(\.path), ["/Users/me/IdeaProjects/api", "/Users/me/IdeaProjects/old"])
        XCTAssertEqual(jetBrains.first?.opened, Date(timeIntervalSince1970: 1_760_000_000))
    }

    func testNamesAndMerging() {
        let cursor = [EditorProject(path: "/Users/me/a", kind: .folder, editor: "Cursor", bundleID: "c", rank: 0),
                      EditorProject(path: "/Users/me/b", kind: .folder, editor: "Cursor", bundleID: "c", rank: 1)]
        let zed = [EditorProject(path: "/Users/me/a", kind: .folder, editor: "Zed", bundleID: "z", rank: 0),
                   EditorProject(path: "/Users/me/a", kind: .folder, editor: "Zed", bundleID: "z", rank: 1)]
        let merged = EditorProjectParsing.merged([cursor, zed])
        XCTAssertEqual(merged.map { "\($0.editor) \($0.path)" }, ["Cursor /Users/me/a", "Zed /Users/me/a", "Cursor /Users/me/b"])
        let workspace = EditorProject(path: "/Users/me/Work/Nimbus App.code-workspace", kind: .workspace, editor: "Cursor", bundleID: "c", rank: 0)
        XCTAssertEqual(workspace.name, "Nimbus App")
        XCTAssertEqual(workspace.folder(home: "/Users/me"), "~/Work")
    }
}
