import XCTest
@testable import SkilliCore

final class VolumeRequestTests: XCTestCase {
    func testALevelSaidInWords() {
        XCTAssertEqual(VolumeRequest.parse("volume 30"), 30)
        XCTAssertEqual(VolumeRequest.parse("volume 30 %"), 30)
        XCTAssertEqual(VolumeRequest.parse("volume 30%"), 30)
        XCTAssertEqual(VolumeRequest.parse("Volume à 30 %"), 30)
        XCTAssertEqual(VolumeRequest.parse("mets le son à 30 %"), 30)
        XCTAssertEqual(VolumeRequest.parse("mets le volume à 45 pour cent"), 45)
        XCTAssertEqual(VolumeRequest.parse("baisse le son à 20"), 20)
        XCTAssertEqual(VolumeRequest.parse("monte le son à 80 s'il te plaît"), 80)
        XCTAssertEqual(VolumeRequest.parse("son 0"), 0)
        XCTAssertEqual(VolumeRequest.parse("set the volume to 30 percent"), 30)
        XCTAssertEqual(VolumeRequest.parse("set volume to 100"), 100)
        XCTAssertEqual(VolumeRequest.parse("vol 15"), 15)
    }

    func testNamedLevels() {
        XCTAssertEqual(VolumeRequest.parse("son au max"), 100)
        XCTAssertEqual(VolumeRequest.parse("mets le son à fond"), 100)
        XCTAssertEqual(VolumeRequest.parse("volume à la moitié"), 50)
        XCTAssertEqual(VolumeRequest.parse("volume half"), 50)
    }

    /// A step, a song, a calculation or another app's sound stay theirs.
    func testWhatIsNotALevel() {
        XCTAssertNil(VolumeRequest.parse("volume"))
        XCTAssertNil(VolumeRequest.parse("monte le son"), "a step, not a level")
        XCTAssertNil(VolumeRequest.parse("monte le son de 10"), "by 10, not to 10")
        XCTAssertNil(VolumeRequest.parse("turn the volume up by 10"))
        XCTAssertNil(VolumeRequest.parse("volume 150"))
        XCTAssertNil(VolumeRequest.parse("30 % de 85"), "a calculation")
        XCTAssertNil(VolumeRequest.parse("volume 3 5"))
        XCTAssertNil(VolumeRequest.parse("le son suivant"))
        XCTAssertNil(VolumeRequest.parse("mets le son de spotify à 30"), "another app's own volume")
        XCTAssertNil(VolumeRequest.parse("son 2 de daft punk"))
    }

    func testTitle() {
        XCTAssertEqual(VolumeRequest.title(30), "Set Volume to 30 %")
    }
}
