import XCTest
@testable import SkilliCore

final class BrewSearchTests: XCTestCase {
    func testRanking() {
        let names = ["ffmpeg@6", "ffmpeg", "ffmpegthumbnailer", "libffmpeg-tools", "jpeg", "ffmpeg2theora", "wget"]
        XCTAssertEqual(BrewSearch.rank("ffmpeg", names), ["ffmpeg", "ffmpeg@6", "ffmpeg2theora", "ffmpegthumbnailer", "libffmpeg-tools"])
        XCTAssertEqual(BrewSearch.rank("tools", names), ["libffmpeg-tools"])
        XCTAssertTrue(BrewSearch.rank("  ", names).isEmpty)
        XCTAssertEqual(BrewSearch.rank("FFMPEG", names, limit: 1), ["ffmpeg"])
    }

    func testOutdatedAndDescriptions() {
        let json = """
        {"formulae":[{"name":"aom","installed_versions":["3.15.1"],"current_version":"3.15.2","pinned":false}],
         "casks":[{"name":"codex","installed_versions":["0.161.0"],"current_version":"0.162.1"}]}
        """
        let outdated = BrewSearch.outdated(Data(json.utf8))
        XCTAssertEqual(outdated["aom"]?.current, "3.15.2")
        XCTAssertEqual(outdated["codex"]?.installed, "0.161.0")
        XCTAssertTrue(BrewSearch.outdated(Data("nope".utf8)).isEmpty)

        let descriptions = BrewSearch.descriptions("ffmpeg: Play, record, convert, and stream audio and video\nfirefox: (Mozilla Firefox) Web browser\nWarning: something: else\n")
        XCTAssertEqual(descriptions["ffmpeg"], "Play, record, convert, and stream audio and video")
        XCTAssertEqual(descriptions["firefox"], "Mozilla Firefox — Web browser")
        XCTAssertNil(descriptions["Warning"], "brew's own messages are not packages")
    }

    func testPackageWords() {
        XCTAssertEqual(BrewPackage(name: "wget", isCask: false, installed: "1.24", update: "1.25").status, "Update 1.24 → 1.25")
        XCTAssertEqual(BrewPackage(name: "wget", isCask: false, installed: "1.24").status, "Installed 1.24")
        XCTAssertEqual(BrewPackage(name: "firefox", isCask: true).status, "Cask")
        XCTAssertEqual(BrewPackage(name: "firefox", isCask: true).page.absoluteString, "https://formulae.brew.sh/cask/firefox")
        XCTAssertEqual(BrewSearch.summary("==> Downloading x\n######## 100%\n==> Pouring wget\n🍺  wget was installed\n"), "==> Pouring wget\n🍺  wget was installed")
    }
}
