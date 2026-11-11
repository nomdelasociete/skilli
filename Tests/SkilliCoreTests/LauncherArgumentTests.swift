import XCTest
@testable import SkilliCore

final class LauncherArgumentTests: XCTestCase {
    private func argument(_ id: String) throws -> LauncherArgument { try XCTUnwrap(LauncherArgument.of(id), id) }

    /// The value typed in the chip is read by the command's own parser.
    func testTheValueIsReadByTheCommandsParser() throws {
        XCTAssertEqual(try argument("system:keepAwake").text("2h").flatMap { AwakeRequest.parse($0) }, .awake(seconds: 7_200))
        XCTAssertEqual(try argument("catalog.awake").text(" 90 min ").flatMap { AwakeRequest.parse($0) }, .awake(seconds: 5_400))
        XCTAssertNotNil(try argument("catalog.awake").text("until 6pm").flatMap { AwakeRequest.parse($0) })
        XCTAssertEqual(try argument("catalog.timer").text("1:30").flatMap(TimerRequest.parse)?.seconds, 90)
        XCTAssertEqual(try argument("catalog.timer").text("10 tea").flatMap(TimerRequest.parse)?.seconds, 600)
        XCTAssertEqual(try argument("catalog.volume").text("30").flatMap(VolumeRequest.parse), 30)
        XCTAssertEqual(try argument("cmd:recordMeeting").text("Weekly sync").flatMap(RecordRequest.name), "Weekly sync")
        XCTAssertNotNil(try argument("catalog.event").text("lunch with Paul tomorrow 1pm").flatMap { EventRequest.parse($0, nounFirst: true) })
        XCTAssertNotNil(try argument("catalog.remind").text("call Paul at 9am").flatMap { ReminderRequest.parse($0) })
    }

    func testNothingTypedOrNotAValueReadsNothing() throws {
        XCTAssertNil(try argument("catalog.awake").text(""))
        XCTAssertNil(try argument("catalog.awake").text("   "))
        XCTAssertNil(try argument("catalog.awake").text("soon").flatMap { AwakeRequest.parse($0) })
        XCTAssertNil(try argument("catalog.volume").text("studio").flatMap(VolumeRequest.parse))
        XCTAssertNil(LauncherArgument.of("cmd:emoji"), "a mode has a filter, not an argument")
    }

    /// ↩ on Keep Awake or Record Meeting acts with no value: ⌘K names the
    /// way to their chip. The others open it with ↩: no action for it.
    func testOnlyACommandThatActsWithNoValueNamesTheWayToItsChip() throws {
        let entries = FeatureCatalog.entries(FeatureCatalog.Input())
        for argument in LauncherArgument.all {
            let entry = try XCTUnwrap(entries.first { $0.id == argument.id }, argument.id)
            if case .type = entry.run {
                XCTAssertNil(argument.ask, argument.id)
            } else {
                XCTAssertEqual(argument.ask?.hasSuffix("…"), true, argument.id)
            }
        }
    }

    /// One declaration per alias id, named as the Catalog names it, with
    /// its example.
    func testEachCommandIsDeclaredOnceAsTheCatalogNamesIt() throws {
        let ids = LauncherArgument.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        let entries = FeatureCatalog.entries(FeatureCatalog.Input())
        for argument in LauncherArgument.all {
            XCTAssertEqual(try XCTUnwrap(entries.first { $0.id == argument.id }, argument.id).title, argument.title)
            XCTAssertFalse(argument.placeholder.isEmpty)
            XCTAssertFalse(argument.chip.isEmpty)
        }
    }
}
