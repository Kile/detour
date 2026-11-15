import XCTest
@testable import SideQuest

final class MapsLauncherTests: XCTestCase {
    let museum = GeoPoint(latitude: 51.519413, longitude: -0.126957)

    func testGoogleMapsLinkGivesDirectionsToThePlace() throws {
        let url = MapsLauncher.googleMapsURL(to: museum, transit: false)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "www.google.com")
        XCTAssertEqual(components.path, "/maps/dir/")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["api"], "1")
        XCTAssertEqual(query["destination"], "51.519413,-0.126957")
        XCTAssertEqual(query["travelmode"], "walking")
        XCTAssertEqual(query.count, 3, "Only the destination is shared, never the player's own location")
        XCTAssertTrue(MapsLauncher.googleMapsURL(to: museum, transit: true).absoluteString.contains("travelmode=transit"))
    }

    func testWalksNearbyAndTakesTransitFurtherAway() {
        let nearby = GeoPoint(latitude: 51.5181, longitude: -0.1240)        // ~250 m
        let farAway = GeoPoint(latitude: 51.4613, longitude: -0.1156)       // Brixton, ~6.5 km
        XCTAssertFalse(MapsLauncher.usesTransit(from: nearby, to: museum))
        XCTAssertTrue(MapsLauncher.usesTransit(from: farAway, to: museum))
        XCTAssertFalse(MapsLauncher.usesTransit(from: nil, to: museum))
    }
}
