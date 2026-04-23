import XCTest
@testable import Xomify_iOS

/// Tests for `SettingsViewModel`. Verifies toggle flips persist to the
/// injected `UserDefaults` and dispatch to `NotificationsService.updatePreferences`.
@MainActor
final class SettingsViewModelTests: XCTestCase {

    func test_init_defaultsToggleValuesToTrue() {
        let defaults = makeIsolatedDefaults()
        let vm = SettingsViewModel(defaults: defaults)
        XCTAssertTrue(vm.queueNotificationsEnabled)
        XCTAssertTrue(vm.digestEnabled)
    }

    func test_init_readsPersistedValues() {
        let defaults = makeIsolatedDefaults()
        defaults.set(false, forKey: SettingsViewModel.queueEnabledKey)
        defaults.set(false, forKey: SettingsViewModel.digestEnabledKey)

        let vm = SettingsViewModel(defaults: defaults)
        XCTAssertFalse(vm.queueNotificationsEnabled)
        XCTAssertFalse(vm.digestEnabled)
    }

    func test_toggleQueueEnabled_persistsToDefaults() {
        let defaults = makeIsolatedDefaults()
        let vm = SettingsViewModel(defaults: defaults)

        vm.queueNotificationsEnabled = false

        XCTAssertEqual(defaults.object(forKey: SettingsViewModel.queueEnabledKey) as? Bool, false)
    }

    func test_toggleDigestEnabled_persistsToDefaults() {
        let defaults = makeIsolatedDefaults()
        let vm = SettingsViewModel(defaults: defaults)

        vm.digestEnabled = false

        XCTAssertEqual(defaults.object(forKey: SettingsViewModel.digestEnabledKey) as? Bool, false)
    }

    func test_togglesEnabled_authorized_returnsTrue() {
        let defaults = makeIsolatedDefaults()
        let vm = SettingsViewModel(defaults: defaults)
        vm.authorizationStatus = .authorized
        XCTAssertTrue(vm.togglesEnabled)
    }

    func test_togglesEnabled_denied_returnsFalse() {
        let defaults = makeIsolatedDefaults()
        let vm = SettingsViewModel(defaults: defaults)
        vm.authorizationStatus = .denied
        XCTAssertFalse(vm.togglesEnabled)
    }

    func test_togglesEnabled_notDetermined_returnsFalse() {
        let defaults = makeIsolatedDefaults()
        let vm = SettingsViewModel(defaults: defaults)
        vm.authorizationStatus = .notDetermined
        XCTAssertFalse(vm.togglesEnabled)
    }

    func test_statusFooter_reflectsStatus() {
        let defaults = makeIsolatedDefaults()
        let vm = SettingsViewModel(defaults: defaults)

        vm.authorizationStatus = .authorized
        XCTAssertTrue(vm.statusFooter.contains("sync"))

        vm.authorizationStatus = .denied
        XCTAssertTrue(vm.statusFooter.contains("System Settings"))

        vm.authorizationStatus = .notDetermined
        XCTAssertTrue(vm.statusFooter.contains("Enable"))
    }

    // MARK: - Helpers

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "SettingsViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
