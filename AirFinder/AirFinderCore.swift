import Foundation
import CoreLocation
import MapKit
import SwiftUI

// MARK: - Models

enum PricingStatus: String, Codable, CaseIterable, Identifiable {
    case free
    case paid
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free:
            return "Free"
        case .paid:
            return "Paid"
        case .unknown:
            return "Unknown"
        }
    }

    var badgeText: String {
        switch self {
        case .free:
            return "Free"
        case .paid:
            return "$"
        case .unknown:
            return "?"
        }
    }

    var tint: Color {
        switch self {
        case .free:
            return Color(red: 0.15, green: 0.72, blue: 0.45)
        case .paid:
            return Color(red: 0.96, green: 0.67, blue: 0.18)
        case .unknown:
            return Color(red: 0.55, green: 0.59, blue: 0.68)
        }
    }
}

enum SubmissionStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case approved
    case rejected

    var id: String { rawValue }
}

struct AirLocation: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var addressLine1: String?
    var city: String?
    var state: String?
    var postalCode: String?
    var latitude: Double
    var longitude: Double
    var pricingStatus: PricingStatus
    var notes: String?
    var source: String
    var lastVerifiedAt: Date?
    var distanceMeters: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var displayAddress: String {
        let parts = [addressLine1, city, state, postalCode]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "No address listed" : parts.joined(separator: ", ")
    }

    var localityDescription: String {
        [city, state]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    var sourceBadge: String {
        if source.lowercased().contains("demo") {
            return "Demo"
        }
        if source.lowercased().contains("crowd") {
            return "Crowd"
        }
        return source.isEmpty ? "Curated" : source.capitalized
    }
}

struct LocationSubmissionDraft: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var addressLine1: String
    var city: String
    var state: String
    var postalCode: String
    var latitude: Double?
    var longitude: Double?
    var pricingStatus: PricingStatus
    var notes: String

    init(
        id: UUID = UUID(),
        name: String = "",
        addressLine1: String = "",
        city: String = "",
        state: String = "",
        postalCode: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        pricingStatus: PricingStatus = .unknown,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.addressLine1 = addressLine1
        self.city = city
        self.state = state
        self.postalCode = postalCode
        self.latitude = latitude
        self.longitude = longitude
        self.pricingStatus = pricingStatus
        self.notes = notes
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func validationErrors() -> [String] {
        var errors: [String] = []

        if name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
            errors.append("Enter a place name.")
        }

        if addressLine1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Enter a street address.")
        }

        if coordinate == nil {
            errors.append("Choose a map location for the submission.")
        }

        return errors
    }
}

enum AirFinderError: LocalizedError, Equatable {
    case invalidDraft([String])
    case duplicateLocation
    case unavailable(String)
    case network(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidDraft(let errors):
            return errors.joined(separator: " ")
        case .duplicateLocation:
            return "A similar location already exists nearby."
        case .unavailable(let message):
            return message
        case .network(let message):
            return message
        case .decoding(let message):
            return message
        }
    }
}

// MARK: - Search and matching

enum LocationSearchEngine {
    static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func matches(_ location: AirLocation, query: String) -> Bool {
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty else { return true }

        let fields = [
            location.name,
            location.addressLine1 ?? "",
            location.city ?? "",
            location.state ?? "",
            location.postalCode ?? "",
            location.notes ?? "",
            location.source
        ]
        .map(normalized)

        return fields.contains { $0.contains(normalizedQuery) }
    }

    static func sort(_ locations: [AirLocation], near coordinate: CLLocationCoordinate2D?) -> [AirLocation] {
        locations.sorted { lhs, rhs in
            switch (lhs.distanceMeters, rhs.distanceMeters) {
            case let (left?, right?):
                if abs(left - right) > 0.5 {
                    return left < right
                }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                break
            }

            if let coordinate {
                let lhsDistance = CLLocation(latitude: lhs.latitude, longitude: lhs.longitude).distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
                let rhsDistance = CLLocation(latitude: rhs.latitude, longitude: rhs.longitude).distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
                if abs(lhsDistance - rhsDistance) > 0.5 {
                    return lhsDistance < rhsDistance
                }
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func filter(_ locations: [AirLocation], query: String, near coordinate: CLLocationCoordinate2D?) -> [AirLocation] {
        let filtered = locations.filter { matches($0, query: query) }
        return sort(filtered, near: coordinate)
    }

    static func isDuplicate(
        candidate: LocationSubmissionDraft,
        against existingLocations: [AirLocation],
        thresholdMeters: CLLocationDistance = 100
    ) -> Bool {
        guard let candidateCoordinate = candidate.coordinate else { return false }

        let candidateName = normalized(candidate.name)
        let candidateAddress = normalized(candidate.addressLine1)

        for location in existingLocations {
            let locationCoordinate = CLLocation(latitude: location.latitude, longitude: location.longitude)
            let candidateLocation = CLLocation(latitude: candidateCoordinate.latitude, longitude: candidateCoordinate.longitude)
            let distance = candidateLocation.distance(from: locationCoordinate)
            guard distance <= thresholdMeters else { continue }

            let locationName = normalized(location.name)
            let locationAddress = normalized(location.addressLine1 ?? "")

            if locationName == candidateName || locationAddress == candidateAddress {
                return true
            }
        }

        return false
    }
}

// MARK: - Backend configuration

struct BackendConfiguration: Equatable {
    let supabaseURL: URL
    let anonKey: String

    static func fromBundle(_ bundle: Bundle = .main) -> BackendConfiguration? {
        let urlString = (bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let anonKey = (bundle.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard
            !urlString.isEmpty,
            !anonKey.isEmpty,
            !urlString.contains("YOUR_SUPABASE"),
            !anonKey.contains("YOUR_SUPABASE"),
            let url = URL(string: urlString)
        else {
            return nil
        }

        return BackendConfiguration(supabaseURL: url, anonKey: anonKey)
    }
}

// MARK: - Store protocol

protocol AirFinderStore {
    func fetchLocations(query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [AirLocation]
    func submitLocation(_ draft: LocationSubmissionDraft) async throws
}

// MARK: - Location permissions

@MainActor
final class LocationAuthorizationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager

    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var currentCoordinate: CLLocationCoordinate2D?

    override init() {
        self.manager = CLLocationManager()
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        self.manager.delegate = self
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdatingLocation() {
        manager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        } else {
            manager.stopUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentCoordinate = locations.last?.coordinate
    }
}

// MARK: - Factory

enum AirFinderStoreFactory {
    static func makeDefault(bundle: Bundle = .main) -> any AirFinderStore {
        if let configuration = BackendConfiguration.fromBundle(bundle) {
            return SupabaseAirFinderStore(configuration: configuration)
        }
        return DemoAirFinderStore(bundle: bundle)
    }
}

// MARK: - View model

@MainActor
final class AirFinderViewModel: ObservableObject {
    enum ActiveSheet: Identifiable, Equatable {
        case detail(AirLocation)
        case submission

        var id: String {
            switch self {
            case .detail(let location):
                return "detail-\(location.id.uuidString)"
            case .submission:
                return "submission"
            }
        }
    }

    @Published var searchText: String = ""
    @Published var locations: [AirLocation] = []
    @Published var selectedSheet: ActiveSheet?
    @Published var submissionDraft: LocationSubmissionDraft = LocationSubmissionDraft()
    @Published var isLoading = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var cameraPosition: MapCameraPosition = .automatic
    @Published var visibleRegion: MKCoordinateRegion?
    @Published var userLocation: CLLocationCoordinate2D?

    let locationManager: LocationAuthorizationManager

    private let store: any AirFinderStore
    private var hasBootstrapped = false
    private var searchTask: Task<Void, Never>?
    private var hasSetInitialCamera = false

    init(
        store: any AirFinderStore = AirFinderStoreFactory.makeDefault(),
        locationManager: LocationAuthorizationManager = LocationAuthorizationManager()
    ) {
        self.store = store
        self.locationManager = locationManager
    }

    func bootstrapIfNeeded() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        locationManager.requestWhenInUseAuthorization()
        await refreshLocations()
    }

    func refreshLocations() async {
        searchTask?.cancel()
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            let fetched = try await store.fetchLocations(query: searchText, near: userLocation ?? visibleRegion?.center)
            locations = fetched

            if !hasSetInitialCamera, let first = fetched.first ?? DemoAirFinderStore.fallbackLocationsForTests.first {
                let region = MKCoordinateRegion(
                    center: first.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.20, longitudeDelta: 0.20)
                )
                cameraPosition = .region(region)
                hasSetInitialCamera = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func scheduleSearchRefresh() {
        searchTask?.cancel()

        let query = searchText
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 275_000_000)
            guard !Task.isCancelled else { return }
            await self?.performSearch(query: query)
        }
    }

    func performSearch(query: String) async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            let fetched = try await store.fetchLocations(query: query, near: userLocation ?? visibleRegion?.center)
            locations = fetched
            statusMessage = fetched.isEmpty ? "No matching air stops found yet." : nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateVisibleRegion(_ region: MKCoordinateRegion?) {
        visibleRegion = region
        if userLocation == nil, let center = region?.center, searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Task { await refreshLocationsAt(center: center) }
        }
    }

    func locationAuthorizationChanged() {
        userLocation = locationManager.currentCoordinate
        if let coordinate = userLocation {
            let region = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.20, longitudeDelta: 0.20)
            )
            cameraPosition = .region(region)
            hasSetInitialCamera = true
            errorMessage = nil
            Task { await refreshLocationsAt(center: coordinate) }
        }
    }

    func select(_ location: AirLocation) {
        selectedSheet = .detail(location)
    }

    func startSubmission(from location: AirLocation? = nil) {
        let coordinate = location?.coordinate ?? userLocation ?? visibleRegion?.center ?? CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298)
        submissionDraft = LocationSubmissionDraft(
            name: location?.name ?? "",
            addressLine1: location?.addressLine1 ?? "",
            city: location?.city ?? "",
            state: location?.state ?? "",
            postalCode: location?.postalCode ?? "",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            pricingStatus: location?.pricingStatus ?? .unknown,
            notes: location?.notes ?? ""
        )
        selectedSheet = .submission
    }

    func submitCurrentDraft() async throws {
        let validationErrors = submissionDraft.validationErrors()
        guard validationErrors.isEmpty else {
            throw AirFinderError.invalidDraft(validationErrors)
        }

        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        try await store.submitLocation(submissionDraft)
        statusMessage = "Submission saved for moderation."
        selectedSheet = nil
        await refreshLocations()
    }

    func dismissMessages() {
        statusMessage = nil
        errorMessage = nil
    }

    func currentMapCenter() -> CLLocationCoordinate2D? {
        visibleRegion?.center ?? userLocation
    }

    private func refreshLocationsAt(center: CLLocationCoordinate2D) async {
        do {
            let fetched = try await store.fetchLocations(query: searchText, near: center)
            locations = fetched
            if !hasSetInitialCamera {
                let region = MKCoordinateRegion(
                    center: center,
                    span: MKCoordinateSpan(latitudeDelta: 0.20, longitudeDelta: 0.20)
                )
                cameraPosition = .region(region)
                hasSetInitialCamera = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Local demo store

actor DemoAirFinderStore: AirFinderStore {
    private let seedLocations: [AirLocation]
    private var pendingSubmissions: [LocationSubmissionDraft] = []
    private let persistenceURL: URL?

    init(bundle: Bundle = .main) {
        self.seedLocations = DemoAirFinderStore.loadSeedLocations(bundle: bundle)
        self.persistenceURL = DemoAirFinderStore.makePersistenceURL()
        self.pendingSubmissions = DemoAirFinderStore.loadPendingSubmissions(from: persistenceURL)
    }

    func fetchLocations(query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [AirLocation] {
        LocationSearchEngine.filter(seedLocations, query: query, near: coordinate)
    }

    func submitLocation(_ draft: LocationSubmissionDraft) async throws {
        let errors = draft.validationErrors()
        guard errors.isEmpty else {
            throw AirFinderError.invalidDraft(errors)
        }

        let existing = seedLocations + pendingSubmissions.compactMap { pendingDraft -> AirLocation? in
            guard let coordinate = pendingDraft.coordinate else { return nil }
            return AirLocation(
                id: pendingDraft.id,
                name: pendingDraft.name,
                addressLine1: pendingDraft.addressLine1,
                city: pendingDraft.city,
                state: pendingDraft.state,
                postalCode: pendingDraft.postalCode,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                pricingStatus: pendingDraft.pricingStatus,
                notes: pendingDraft.notes,
                source: "pending-submission",
                lastVerifiedAt: nil,
                distanceMeters: nil
            )
        }

        guard !LocationSearchEngine.isDuplicate(candidate: draft, against: existing) else {
            throw AirFinderError.duplicateLocation
        }

        pendingSubmissions.append(draft)
        try persistPendingSubmissions()
    }

    private static func loadSeedLocations(bundle: Bundle) -> [AirLocation] {
        guard let url = bundle.url(forResource: "SeedLocations", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            return DemoAirFinderStore.fallbackSeedLocations
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let seeds = try? decoder.decode([AirLocation].self, from: data) {
            return seeds
        }

        return DemoAirFinderStore.fallbackSeedLocations
    }

    private static func makePersistenceURL() -> URL? {
        do {
            let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let folder = base.appendingPathComponent("AirFinder", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
            return folder.appendingPathComponent("pending-submissions.json")
        } catch {
            return nil
        }
    }

    private static func loadPendingSubmissions(from url: URL?) -> [LocationSubmissionDraft] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        return (try? decoder.decode([LocationSubmissionDraft].self, from: data)) ?? []
    }

    private func persistPendingSubmissions() throws {
        guard let persistenceURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(pendingSubmissions)
        try data.write(to: persistenceURL, options: [.atomic])
    }

    static var fallbackLocationsForTests: [AirLocation] {
        fallbackSeedLocations
    }

    private static let fallbackSeedLocations: [AirLocation] = [
        AirLocation(
            id: UUID(uuidString: "2D42C1A3-0F6E-4C54-8D52-2F96C8E3D101") ?? UUID(),
            name: "Demo Free Air - West Loop",
            addressLine1: "1200 W Randolph St",
            city: "Chicago",
            state: "IL",
            postalCode: "60607",
            latitude: 41.8842,
            longitude: -87.6592,
            pricingStatus: .free,
            notes: "Demo seed entry. Replace with verified locations before launch.",
            source: "demo-seed",
            lastVerifiedAt: Date(timeIntervalSince1970: 1_725_000_000),
            distanceMeters: nil
        ),
        AirLocation(
            id: UUID(uuidString: "7E92E7A2-DB55-4C28-9AF1-39A0B66A2A02") ?? UUID(),
            name: "Demo Paid Air - South Loop",
            addressLine1: "1550 S Wabash Ave",
            city: "Chicago",
            state: "IL",
            postalCode: "60605",
            latitude: 41.8605,
            longitude: -87.6254,
            pricingStatus: .paid,
            notes: "Demo seed entry. Marked paid with a dollar-sign badge.",
            source: "demo-seed",
            lastVerifiedAt: Date(timeIntervalSince1970: 1_725_000_000),
            distanceMeters: nil
        ),
        AirLocation(
            id: UUID(uuidString: "C8AE7A93-5D06-4D85-8D91-BF1E8E0A3A03") ?? UUID(),
            name: "Demo Free Air - Lakeview",
            addressLine1: "3200 N Clark St",
            city: "Chicago",
            state: "IL",
            postalCode: "60657",
            latitude: 41.9389,
            longitude: -87.6533,
            pricingStatus: .free,
            notes: "Demo seed entry for nearby search behavior.",
            source: "demo-seed",
            lastVerifiedAt: Date(timeIntervalSince1970: 1_725_000_000),
            distanceMeters: nil
        ),
        AirLocation(
            id: UUID(uuidString: "1B7A66CF-5A2E-40B2-8D73-7D1AB2C4E304") ?? UUID(),
            name: "Demo Unknown Air - Evanston",
            addressLine1: "1700 Sherman Ave",
            city: "Evanston",
            state: "IL",
            postalCode: "60201",
            latitude: 42.0462,
            longitude: -87.6940,
            pricingStatus: .unknown,
            notes: "Demo seed entry with unknown pricing.",
            source: "demo-seed",
            lastVerifiedAt: Date(timeIntervalSince1970: 1_725_000_000),
            distanceMeters: nil
        ),
        AirLocation(
            id: UUID(uuidString: "A0C0E28E-5F73-4A69-8C6E-10B176D2A505") ?? UUID(),
            name: "Demo Free Air - Oak Park",
            addressLine1: "714 Lake St",
            city: "Oak Park",
            state: "IL",
            postalCode: "60301",
            latitude: 41.8889,
            longitude: -87.7885,
            pricingStatus: .free,
            notes: "Demo seed entry west of the city.",
            source: "demo-seed",
            lastVerifiedAt: Date(timeIntervalSince1970: 1_725_000_000),
            distanceMeters: nil
        )
    ]
}

// MARK: - Supabase store

actor SupabaseAirFinderStore: AirFinderStore {
    private let configuration: BackendConfiguration
    private let session: URLSession

    init(configuration: BackendConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func fetchLocations(query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [AirLocation] {
        struct SearchRequest: Encodable {
            let query: String
            let latitude: Double?
            let longitude: Double?
            let radiusMeters: Int
            let limitCount: Int
        }

        let requestBody = SearchRequest(
            query: query,
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
            radiusMeters: 50_000,
            limitCount: 50
        )

        let rows: [SupabaseLocationRow] = try await performRPC(
            "search_locations",
            body: requestBody
        )

        return rows.map { $0.asAirLocation }
    }

    func submitLocation(_ draft: LocationSubmissionDraft) async throws {
        let errors = draft.validationErrors()
        guard errors.isEmpty else {
            throw AirFinderError.invalidDraft(errors)
        }

        guard let coordinate = draft.coordinate else {
            throw AirFinderError.invalidDraft(["Choose a map location for the submission."])
        }

        struct SubmitRequest: Encodable {
            let name: String
            let addressLine1: String
            let city: String
            let state: String
            let postalCode: String
            let notes: String
            let pricingStatus: String
            let latitude: Double
            let longitude: Double
        }

        let body = SubmitRequest(
            name: draft.name,
            addressLine1: draft.addressLine1,
            city: draft.city,
            state: draft.state,
            postalCode: draft.postalCode,
            notes: draft.notes,
            pricingStatus: draft.pricingStatus.rawValue,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )

        _ = try await performRPC("submit_location", body: body, expectResponse: Bool.self)
    }

    private func performRPC<T: Decodable, Body: Encodable>(
        _ function: String,
        body: Body,
        expectResponse _: T.Type = T.self
    ) async throws -> T {
        let url = configuration.supabaseURL
            .appendingPathComponent("rest")
            .appendingPathComponent("v1")
            .appendingPathComponent("rpc")
            .appendingPathComponent(function)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder.supabase.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AirFinderError.network("The backend did not return a valid response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown backend error."
            throw AirFinderError.network(message)
        }

        if T.self == Bool.self {
            return true as! T
        }

        let decoder = JSONDecoder.supabase
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AirFinderError.decoding("Could not decode backend response.")
        }
    }
}

private struct SupabaseLocationRow: Decodable {
    let id: UUID
    let name: String
    let addressLine1: String?
    let city: String?
    let state: String?
    let postalCode: String?
    let latitude: Double
    let longitude: Double
    let pricingStatus: PricingStatus
    let notes: String?
    let source: String
    let lastVerifiedAt: Date?
    let distanceMeters: Double?

    var asAirLocation: AirLocation {
        AirLocation(
            id: id,
            name: name,
            addressLine1: addressLine1,
            city: city,
            state: state,
            postalCode: postalCode,
            latitude: latitude,
            longitude: longitude,
            pricingStatus: pricingStatus,
            notes: notes,
            source: source,
            lastVerifiedAt: lastVerifiedAt,
            distanceMeters: distanceMeters
        )
    }
}

private extension JSONEncoder {
    static let supabase: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private extension JSONDecoder {
    static let supabase: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
