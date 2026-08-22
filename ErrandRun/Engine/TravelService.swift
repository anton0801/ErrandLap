//
//  TravelService.swift
//  ErrandRun
//
//  The one thing the map service is used for: real travel time between points.
//

import Foundation
import CoreLocation
import MapKit

enum TravelError: LocalizedError {
    case offline
    case notFound
    case noAddress

    var errorDescription: String? {
        switch self {
        case .offline:
            return "Offline. Enter the travel time by hand, or add it later. Everything else works."
        case .notFound:
            return "No route found between these two points. Enter the travel time by hand."
        case .noAddress:
            return "This point has no address yet. Add one, or enter the travel time by hand."
        }
    }
}

struct TravelService {
    static func geocode(_ address: String) async throws -> GeoPoint {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TravelError.noAddress }
        do {
            let placemarks = try await CLGeocoder().geocodeAddressString(trimmed)
            guard let location = placemarks.first?.location else { throw TravelError.notFound }
            return GeoPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        } catch let error as CLError {
            throw error.code == .network ? TravelError.offline : TravelError.notFound
        } catch let error as TravelError {
            throw error
        } catch {
            throw TravelError.notFound
        }
    }

    static func minutes(from: GeoPoint, to: GeoPoint, mode: TravelMode, pace: WalkingPace) async throws -> Int {
        let request = MKDirections.Request()
        request.source = mapItem(from)
        request.destination = mapItem(to)
        request.transportType = transportType(for: mode)

        do {
            // MapKit has no bicycle routing: take the walking route's distance and ride it.
            if mode == .cycling {
                let response = try await MKDirections(request: request).calculate()
                guard let route = response.routes.first else { throw TravelError.notFound }
                let kilometres = route.distance / 1000
                return max(1, Int((kilometres / mode.speed(pace: pace) * 60).rounded(.up)))
            }
            let response = try await MKDirections(request: request).calculateETA()
            return max(1, Int((response.expectedTravelTime / 60).rounded(.up)))
        } catch let error as MKError {
            switch error.code {
            case .loadingThrottled, .serverFailure:
                throw TravelError.offline
            case .directionsNotFound, .placemarkNotFound:
                if mode == .transit || mode == .mixed {
                    // Not every city has transit directions. Fall back to driving.
                    let fallback = MKDirections.Request()
                    fallback.source = mapItem(from)
                    fallback.destination = mapItem(to)
                    fallback.transportType = .automobile
                    if let response = try? await MKDirections(request: fallback).calculateETA() {
                        return max(1, Int((response.expectedTravelTime / 60).rounded(.up)))
                    }
                }
                throw TravelError.notFound
            default:
                throw TravelError.notFound
            }
        } catch let error as NSError where error.domain == NSURLErrorDomain {
            throw TravelError.offline
        } catch let error as TravelError {
            throw error
        } catch {
            throw TravelError.notFound
        }
    }

    private static func mapItem(_ point: GeoPoint) -> MKMapItem {
        MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)))
    }

    private static func transportType(for mode: TravelMode) -> MKDirectionsTransportType {
        switch mode {
        case .walking: return .walking
        case .cycling: return .walking
        case .driving: return .automobile
        case .transit: return .transit
        case .mixed: return .transit
        }
    }
}
