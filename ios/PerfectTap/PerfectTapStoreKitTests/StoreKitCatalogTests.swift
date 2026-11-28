import XCTest
import StoreKit
import StoreKitTest
@testable import PerfectTap

/// Serial StoreKit lifecycle tests. This target does not also attach a StoreKit
/// configuration to its scheme; the session owns the explicit file URL.
@MainActor
final class StoreKitCatalogTests: XCTestCase {
    private var allProductIDs: Set<String> {
        Set(CoinPackID.allCases.map(\.rawValue) + SpecialProductID.allCases.map(\.rawValue) + ShopItem.premiumProductIDs)
    }

    private func configurationURL() throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PerfectTap", withExtension: "storekit"))
    }

    func testConfigurationFileMatchesCode() throws {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: configurationURL())) as? [String: Any])
        let products = try XCTUnwrap(json["products"] as? [[String: Any]])
        XCTAssertEqual(products.count, 9)
        var types: [String: String] = [:]
        for product in products {
            let id = try XCTUnwrap(product["productID"] as? String)
            types[id] = product["type"] as? String
            XCTAssertFalse((product["referenceName"] as? String ?? "").isEmpty, "Missing reference name: \(id)")
            let price = try XCTUnwrap(Decimal(string: product["displayPrice"] as? String ?? ""))
            XCTAssertGreaterThan(price, 0, "Invalid local StoreKit test price: \(id)")
            let localizations = try XCTUnwrap(product["localizations"] as? [[String: Any]])
            let english = try XCTUnwrap(localizations.first { ($0["locale"] as? String) == "en_US" })
            XCTAssertFalse((english["displayName"] as? String ?? "").isEmpty, "Missing localized name: \(id)")
            XCTAssertFalse((english["description"] as? String ?? "").isEmpty, "Missing localized description: \(id)")
        }
        XCTAssertEqual(Set(types.keys), allProductIDs)
        for pack in CoinPackID.allCases { XCTAssertEqual(types[pack.rawValue], "Consumable") }
        XCTAssertEqual(types[SpecialProductID.removeAds.rawValue], "NonConsumable")
        for id in ShopItem.premiumProductIDs { XCTAssertEqual(types[id], "NonConsumable") }
    }

    func testSessionCanPurchaseEveryProduct() throws {
        let session = try SKTestSession(contentsOf: configurationURL())
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        for productID in allProductIDs.sorted() {
            _ = try session.buyProduct(productIdentifier: productID)
        }
        XCTAssertEqual(Set(session.allTransactions().map(\.productIdentifier)), allProductIDs,
                       "StoreKitTest must purchase the complete catalog")
    }
}
