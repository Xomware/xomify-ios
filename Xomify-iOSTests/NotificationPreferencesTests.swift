import XCTest
@testable import Xomify_iOS

/// Coverage for the per-kind preference model B8 shipped untested.
final class NotificationPreferencesTests: XCTestCase {

    func test_absentFlagResolvesToTheRegistryDefault() async {
        // This is the whole no-backfill migration story: an untouched flag
        // means "use the default", never false.
        let prefs = NotificationPreferences()
        XCTAssertTrue(prefs.isEnabled("shareReceivedEnabled", default: true))
        XCTAssertFalse(prefs.isEnabled("digestEnabled", default: false))
    }

    func test_storedFlagBeatsTheDefault() async {
        var prefs = NotificationPreferences()
        prefs.set("shareReceivedEnabled", false)
        XCTAssertFalse(prefs.isEnabled("shareReceivedEnabled", default: true))
    }

    func test_writesStaySparse() async {
        // Only what the user touched is ever sent. Sending all sixteen would
        // freeze today's defaults onto the device row and break the backend's
        // absent-means-default fallback.
        var prefs = NotificationPreferences()
        prefs.set("digestEnabled", true)
        XCTAssertEqual(prefs.flags, ["digestEnabled": true])
    }

    func test_serverMapIsAuthoritativeOnMerge() async {
        // The server knows about kinds this build may not have shipped with.
        var prefs = NotificationPreferences(flags: ["digestEnabled": true])
        prefs.merge(server: ["digestEnabled": false, "aFutureKindEnabled": true])
        XCTAssertFalse(prefs.isEnabled("digestEnabled", default: false))
        XCTAssertTrue(prefs.isEnabled("aFutureKindEnabled", default: false))
    }

    // MARK: - Catalog

    func test_catalogCoversEveryPushKind() async {
        // A kind with no Settings row is one the user can never turn off.
        let kinds = Set(PushKind.allCases.map(\.rawValue)).subtracting(["unknown"])
        XCTAssertEqual(NotificationCatalog.all.count, kinds.count,
                       "every push kind needs exactly one Settings row")
    }

    func test_catalogFlagNamesAreUnique() async {
        // Two rows sharing a flag would make one toggle mute both.
        let ids = NotificationCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func test_everyRowHasCopy() async {
        for setting in NotificationCatalog.all {
            XCTAssertFalse(setting.title.isEmpty, "\(setting.id) has no title")
            XCTAssertFalse(setting.subtitle.isEmpty, "\(setting.id) has no subtitle")
        }
    }

    func test_digestIsTheOnlyRowOffByDefault() async {
        // Mirrors the backend registry, where digest is the one opt-in kind.
        let off = NotificationCatalog.all.filter { !$0.defaultEnabled }.map(\.id)
        XCTAssertEqual(off, ["digestEnabled"])
    }

    func test_everySectionHasRows() async {
        for section in NotificationSection.allCases {
            XCTAssertFalse(NotificationCatalog.settings(in: section).isEmpty,
                           "\(section.title) has no rows")
        }
    }
}
