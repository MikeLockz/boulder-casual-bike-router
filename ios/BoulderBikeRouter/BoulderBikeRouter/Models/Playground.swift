import Foundation
import CoreLocation

/// Represents a playground location parsed from the backend API.
struct Playground: Codable, Identifiable, Hashable {
    var id: String { name } // Name is unique in the dropdown list
    
    let lat: Double
    let lon: Double
    let name: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
