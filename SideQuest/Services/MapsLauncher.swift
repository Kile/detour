import MapKit
import UIKit

/// Where "Open in Maps" can send the player.
enum MapsApp: String, CaseIterable, Identifiable {
    case apple
    case google

    var id: String { rawValue }
    var title: String { self == .apple ? "Apple Maps" : "Google Maps" }
}

/// Opens a quest's target place with directions from wherever the player is. Only the target (a public
/// place from Apple Maps) is handed over; the maps app works out your own location itself.
enum MapsLauncher {
    /// Walk to anything within 2 km, otherwise take public transport (same split as the time trial estimate).
    static func usesTransit(from origin: GeoPoint?, to target: GeoPoint) -> Bool {
        guard let origin else { return false }
        return Geofence.distance(origin, target) > 2_000
    }

    /// A Google Maps URL: opens the Google Maps app if it's installed, otherwise the website.
    static func googleMapsURL(to target: GeoPoint, transit: Bool) -> URL {
        var components = URLComponents(string: "https://www.google.com/maps/dir/")!
        components.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: String(format: "%.6f,%.6f", target.latitude, target.longitude)),
            URLQueryItem(name: "travelmode", value: transit ? "transit" : "walking"),
        ]
        return components.url!
    }

    @MainActor
    static func open(_ app: MapsApp, target: GeoPoint, name: String, origin: GeoPoint?) {
        let transit = usesTransit(from: origin, to: target)
        switch app {
        case .apple:
            let coordinate = CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude)
            let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
            item.name = name
            item.openInMaps(launchOptions: [
                MKLaunchOptionsDirectionsModeKey: transit ? MKLaunchOptionsDirectionsModeTransit : MKLaunchOptionsDirectionsModeWalking,
            ])
        case .google:
            UIApplication.shared.open(googleMapsURL(to: target, transit: transit))
        }
    }
}
