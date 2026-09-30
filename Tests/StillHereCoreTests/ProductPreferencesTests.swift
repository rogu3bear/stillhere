import Foundation
import Testing
@testable import StillHereCore

@Suite struct ProductPreferencesTests {
    @Test func renamePreservesSettingsWithoutOverwritingNewChoices() throws {
        let legacyDomain = "stillhere.tests.legacy.\(UUID().uuidString)"
        let currentDomain = "stillhere.tests.current.\(UUID().uuidString)"
        let legacy = try #require(UserDefaults(suiteName: legacyDomain))
        let current = try #require(UserDefaults(suiteName: currentDomain))
        defer {
            legacy.removePersistentDomain(forName: legacyDomain)
            current.removePersistentDomain(forName: currentDomain)
        }
        legacy.set(30.0, forKey: "refreshInterval")
        legacy.set(false, forKey: "probeHTTP")
        legacy.set("com.apple.Terminal", forKey: "terminalBundleID")
        legacy.set([8123], forKey: IgnoreConfiguration.PreferenceKey.ports)
        legacy.set("unrelated", forKey: "notAProductSetting")
        current.set(10.0, forKey: "refreshInterval")

        ProductPreferences.migrate(from: legacy, into: current)
        #expect(current.double(forKey: "refreshInterval") == 10)
        #expect(current.object(forKey: "probeHTTP") as? Bool == false)
        #expect(current.string(forKey: "terminalBundleID") == "com.apple.Terminal")
        #expect(IgnoreConfiguration.saved(domain: currentDomain).ports == [8123])
        #expect(current.object(forKey: "notAProductSetting") == nil)
        #expect(legacy.array(forKey: IgnoreConfiguration.PreferenceKey.ports) as? [Int] == [8123])

        // A later reset must not resurrect preferences from the old product.
        current.removeObject(forKey: "probeHTTP")
        current.set([], forKey: IgnoreConfiguration.PreferenceKey.ports)
        ProductPreferences.migrate(from: legacy, into: current)
        #expect(current.object(forKey: "probeHTTP") == nil)
        #expect(IgnoreConfiguration.saved(domain: currentDomain).ports.isEmpty)
    }
}
