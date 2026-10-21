import XCTest
@testable import SkilliCore

final class BluetoothRouteTests: XCTestCase {
    func testKindFromTheClassOfDevice() {
        XCTAssertEqual(BluetoothRoute.Kind(major: 0x04, minor: 6, name: "AirPods Pro de Camille"), .headphones)
        XCTAssertEqual(BluetoothRoute.Kind(major: 0x04, minor: 1, name: "Jabra"), .headphones, "a wearable headset")
        XCTAssertEqual(BluetoothRoute.Kind(major: 0x04, minor: 5, name: "Salon"), .speaker)
        XCTAssertEqual(BluetoothRoute.Kind(major: 0x05, minor: 0x10, name: "Magic Keyboard"), .keyboard)
        XCTAssertEqual(BluetoothRoute.Kind(major: 0x05, minor: 0x20, name: "Magic Mouse"), .mouse)
        XCTAssertEqual(BluetoothRoute.Kind(major: 0x05, minor: 0x20, name: "Magic Trackpad de Jean-François"), .trackpad)
        XCTAssertEqual(BluetoothRoute.Kind(major: 0x05, minor: 0x02, name: "Xbox Wireless Controller"), .gamepad)
        XCTAssertEqual(BluetoothRoute.Kind(major: 0x02, minor: 3, name: "iPhone"), .phone)
        XCTAssertEqual(BluetoothRoute.Kind(major: 0x01, minor: 3, name: "Jb’s MacBook Pro"), .computer)
        XCTAssertEqual(BluetoothRoute.Kind(major: 0x07, minor: 1, name: "Apple Watch de Jean-François"), .watch)
        XCTAssertEqual(BluetoothRoute.Kind(major: 0x1F, minor: 0, name: "AirPods"), .headphones, "unclassified, known by its name")
    }

    func testWordsForTheLauncherAndAsk() {
        XCTAssertEqual(BluetoothRoute.title(name: "AirPods Pro", connect: true), "Connect AirPods Pro")
        XCTAssertEqual(BluetoothRoute.title(name: "AirPods Pro", connect: false), "Disconnect AirPods Pro")
        XCTAssertTrue(BluetoothRoute.keywords(kind: .headphones, connect: true).contains("casque"))
        XCTAssertTrue(BluetoothRoute.description(name: "AirPods Pro", kind: .headphones, connect: true).hasPrefix("Connect Bluetooth headphones"))
        XCTAssertEqual(BluetoothRoute.symbol(name: "AirPods Pro de Camille", kind: .headphones), "airpodspro")
        XCTAssertEqual(BluetoothRoute.symbol(name: "Magic Keyboard", kind: .keyboard), "keyboard")
    }

    func testTheDeviceWordsPointTo() {
        let devices: [(name: String, kind: BluetoothRoute.Kind)] = [
            ("AirPods Pro 2 de Jf", .headphones), ("AirPods Pro de Jean-François", .headphones),
            ("Magic Keyboard de Jf", .keyboard), ("Salon", .speaker)
        ]
        XCTAssertEqual(BluetoothRoute.match("AirPods Pro 2", among: devices), 0)
        XCTAssertEqual(BluetoothRoute.match("jean-françois", among: devices), 1)
        XCTAssertNil(BluetoothRoute.match("mes airpods", among: devices), "two AirPods: say which")
        XCTAssertEqual(BluetoothRoute.match("le clavier", among: devices), 2)
        XCTAssertEqual(BluetoothRoute.match("l'enceinte", among: devices), 3)
        XCTAssertEqual(BluetoothRoute.match("salon", among: devices), 3)
        XCTAssertNil(BluetoothRoute.match("la télé", among: devices))
    }

    func testMentions() {
        XCTAssertTrue(BluetoothRoute.mentions("connecte mes AirPods"))
        XCTAssertTrue(BluetoothRoute.mentions("bluetooth"))
        XCTAssertFalse(BluetoothRoute.mentions("mets le son sur mes AirPods"), "a sound output, not a connection")
    }
}
