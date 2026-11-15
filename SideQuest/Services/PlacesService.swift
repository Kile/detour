import Foundation
import MapKit

/// Keeps unsuitable places (alcohol, gambling, age-restricted) out of the AI's context entirely.
enum PlaceFilter {
    static let excludedCategoryRawValues: Set<String> = [
        "MKPOICategoryNightlife", "MKPOICategoryBrewery", "MKPOICategoryWinery", "MKPOICategoryDistillery",
        "MKPOICategoryCasino", "MKPOICategoryPolice", "MKPOICategoryFireStation", "MKPOICategoryHospital",
        "MKPOICategoryAirport", "MKPOICategoryParking", "MKPOICategoryEVCharger", "MKPOICategoryGasStation",
    ]

    static let excludedNameWords: [String] = [
        "pub", "bar", "tavern", "inn", "brewery", "brewing", "wine", "winery", "distillery", "liquor", "off licence",
        "off-licence", "casino", "betting", "bookmaker", "bookies", "ladbrokes", "william hill", "coral", "paddy power",
        "vape", "vaping", "tobacco", "tobacconist", "smoke shop", "shisha", "hookah", "cannabis", "cbd", "nightclub",
        "night club", "strip", "adult", "sex shop", "gentlemen's club", "arms", "gun", "pawn",
    ]

    static func isAllowed(name: String, categoryRawValue: String?) -> Bool {
        if let category = categoryRawValue, excludedCategoryRawValues.contains(category) { return false }
        let words = Set(TextRules.normalizedName(name).split(separator: " ").map(String.init))
        let normalized = " " + TextRules.normalizedName(name) + " "
        for term in excludedNameWords {
            let normalizedTerm = TextRules.normalizedName(term)
            if normalizedTerm.contains(" ") {
                if normalized.contains(" \(normalizedTerm) ") { return false }
            } else if words.contains(normalizedTerm) {
                return false
            }
        }
        return true
    }

    /// "MKPOICategoryNationalPark" → "national park".
    static func readableCategory(_ rawValue: String?) -> String {
        guard var raw = rawValue, !raw.isEmpty else { return "place" }
        raw = raw.replacingOccurrences(of: "MKPOICategory", with: "")
        var words: [String] = []
        var current = ""
        for character in raw {
            if character.isUppercase, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        return words.joined(separator: " ").lowercased()
    }
}

/// Finds real places with MapKit. Only names/categories/distances leave the device.
struct PlacesService {
    var maxPlaces = 25

    func places(around location: CLLocation, scope: QuestScope, theme: QuestTheme?) async -> [Place] {
        var items: [MKMapItem] = []
        let radius = scope.searchRadius

        if scope == .nearby {
            let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: radius)
            request.pointOfInterestFilter = .includingAll
            if let response = try? await MKLocalSearch(request: request).start() {
                items += response.mapItems
            }
        }

        var queries = theme?.placeQueries ?? []
        if scope == .city {
            queries += ["landmark", "museum", "gallery", "market", "historic site", "square"]
        } else {
            queries += ["park", "shop", "cafe"]
        }
        let region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
        await withTaskGroup(of: [MKMapItem].self) { group in
            for query in Set(queries) {
                group.addTask {
                    let request = MKLocalSearch.Request()
                    request.naturalLanguageQuery = query
                    request.region = region
                    request.resultTypes = .pointOfInterest
                    return (try? await MKLocalSearch(request: request).start())?.mapItems ?? []
                }
            }
            for await result in group { items += result }
        }

        var seen = Set<String>()
        var places: [Place] = []
        for item in items {
            guard let name = item.name, !name.isEmpty else { continue }
            let key = TextRules.normalizedName(name)
            guard !seen.contains(key) else { continue }
            let coordinate = item.placemark.coordinate
            let distance = location.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            guard distance <= radius * 1.1 else { continue }
            let category = item.pointOfInterestCategory?.rawValue
            guard PlaceFilter.isAllowed(name: name, categoryRawValue: category) else { continue }
            seen.insert(key)
            places.append(Place(name: name, category: PlaceFilter.readableCategory(category),
                                distanceMeters: Int(distance.rounded()),
                                coordinate: GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)))
        }
        // A mix of close and further places, closest first.
        return Array(places.sorted { $0.distanceMeters < $1.distanceMeters }.prefix(maxPlaces))
    }
}
