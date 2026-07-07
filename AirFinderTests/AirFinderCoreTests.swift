import XCTest
import CoreLocation
@testable import AirFinder

final class AirFinderCoreTests: XCTestCase {
    func testPricingStatusLabels() {
        XCTAssertEqual(PricingStatus.free.title, "Free")
        XCTAssertEqual(PricingStatus.free.badgeText, "Free")
        XCTAssertEqual(PricingStatus.paid.badgeText, "$")
        XCTAssertEqual(PricingStatus.unknown.title, "Unknown")
    }

    func testDraftValidationRejectsIncompleteEntries() {
        let draft = LocationSubmissionDraft()
        let errors = draft.validationErrors()
        XCTAssertTrue(errors.contains("Enter a place name."))
        XCTAssertTrue(errors.contains("Enter a street address."))
        XCTAssertTrue(errors.contains("Choose a map location for the submission."))
    }

    func testSearchMatchesCityAndAddress() {
        let locations = DemoAirFinderStore.fallbackLocationsForTests
        let results = LocationSearchEngine.filter(
            locations,
            query: "Lakeview",
            near: CLLocationCoordinate2D(latitude: 41.92, longitude: -87.65)
        )

        XCTAssertEqual(results.first?.name, "Demo Free Air - Lakeview")
    }

    func testDuplicateDetectionUsesNameAndProximity() {
        let existing = DemoAirFinderStore.fallbackLocationsForTests
        let duplicateDraft = LocationSubmissionDraft(
            name: "Demo Free Air - Lakeview",
            addressLine1: "3200 N Clark St",
            city: "Chicago",
            state: "IL",
            postalCode: "60657",
            latitude: 41.9390,
            longitude: -87.6532,
            pricingStatus: .free
        )

        XCTAssertTrue(LocationSearchEngine.isDuplicate(candidate: duplicateDraft, against: existing))
    }

    func testDuplicateDetectionRejectsFarAwayLocations() {
        let existing = DemoAirFinderStore.fallbackLocationsForTests
        let uniqueDraft = LocationSubmissionDraft(
            name: "Interstate Service Stop",
            addressLine1: "1000 Market St",
            city: "San Francisco",
            state: "CA",
            postalCode: "94103",
            latitude: 37.7749,
            longitude: -122.4194,
            pricingStatus: .paid
        )

        XCTAssertFalse(LocationSearchEngine.isDuplicate(candidate: uniqueDraft, against: existing))
    }
}
