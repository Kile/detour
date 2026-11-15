import Foundation

/// Checks the player is within the quest radius when they take the photo (Nearby/City only).
enum Geofence {
    enum Result: Equatable {
        case inside(distance: Double)
        case outside(distance: Double, radius: Double)
        /// The location fix is too vague to judge.
        case tooInaccurate(accuracy: Double)
    }

    /// GPS slack we allow on top of the radius.
    static let maxAccuracyAllowance: Double = 100
    /// Fixes worse than this are rejected rather than guessed at.
    static let worstUsableAccuracy: Double = 1_000

    static func radius(scope: QuestScope, hasSpecificTarget: Bool) -> Double {
        switch (scope, hasSpecificTarget) {
        case (.nearby, true): return 200
        case (.nearby, false): return 1_500
        case (.city, true): return 300
        case (.city, false): return 25_000
        case (.venue, _): return .infinity
        }
    }

    static func check(user: GeoPoint, horizontalAccuracy: Double, center: GeoPoint, radius: Double) -> Result {
        if horizontalAccuracy < 0 || horizontalAccuracy > worstUsableAccuracy {
            return .tooInaccurate(accuracy: horizontalAccuracy)
        }
        let d = distance(user, center)
        let allowed = radius + min(horizontalAccuracy, maxAccuracyAllowance)
        return d <= allowed ? .inside(distance: d) : .outside(distance: d, radius: radius)
    }

    /// Great-circle distance in metres (haversine).
    static func distance(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * atan2(sqrt(h), sqrt(1 - h))
    }

    static func friendlyDistance(_ metres: Double) -> String {
        metres >= 1_000 ? String(format: "%.1f km", metres / 1_000) : "\(Int(metres.rounded())) m"
    }
}
