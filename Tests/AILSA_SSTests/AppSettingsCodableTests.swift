import XCTest
@testable import AILSA_SS

final class AppSettingsCodableTests: XCTestCase {
    func testDecodeSettingsRequiresFullCurrentShape() throws {
        let json = """
        {
          "launchAtStartup": true,
          "launchCodexAfterSwitch": true,
          "autoSmartSwitch": false,
          "syncOpencodeOpenaiAuth": false
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8)))
    }

    /// A settings.json written by a build that still shipped the proxy stack
    /// must keep loading, and its proxy keys must survive a save so an older
    /// build can still read the file back.
    func testLegacyProxyKeysAreCarriedThroughRoundTrip() throws {
        let json = """
        {
          "launchAtStartup": true,
          "launchCodexAfterSwitch": true,
          "autoSmartSwitch": false,
          "syncOpencodeOpenaiAuth": false,
          "localProxyHostAPIOnly": true,
          "restartEditorsOnSwitch": false,
          "restartEditorTargets": [],
          "autoStartApiProxy": true,
          "proxyConfiguration": {"preferredPortText": "4141"},
          "remoteServers": [{"id": "a", "host": "example.invalid"}],
          "locale": "en"
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.legacyPassthrough.keys.sorted(), AppSettings.legacyPassthroughKeys.sorted())

        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
        XCTAssertEqual(object["autoStartApiProxy"] as? Bool, true)
        XCTAssertEqual(object["localProxyHostAPIOnly"] as? Bool, true)
        XCTAssertEqual((object["remoteServers"] as? [[String: Any]])?.first?["host"] as? String, "example.invalid")
    }

    func testFreshSettingsDoNotEmitLegacyProxyKeys() throws {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings.defaultValue)) as! [String: Any]
        for key in AppSettings.legacyPassthroughKeys {
            XCTAssertNil(object[key], key)
        }
    }

    func testDecodeSettingsWithoutUsageProgressDisplayModeDefaultsToUsed() throws {
        let json = """
        {
          "launchAtStartup": true,
          "launchCodexAfterSwitch": true,
          "autoSmartSwitch": false,
          "syncOpencodeOpenaiAuth": false,
          "localProxyHostAPIOnly": false,
          "restartEditorsOnSwitch": false,
          "restartEditorTargets": [],
          "autoStartApiProxy": false,
          "proxyConfiguration": {
            "preferredPortText": "4141",
            "cloudflared": {
              "enabled": false,
              "tunnelMode": "quick",
              "useHTTP2": false,
              "namedHostname": ""
            }
          },
          "remoteServers": [],
          "locale": "en"
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.usageProgressDisplayMode, .used)
        XCTAssertEqual(settings.quotaVisibility, .defaultValue)
        XCTAssertFalse(settings.launchAntigravityAfterSwitch)
        XCTAssertFalse(settings.autoSmartSwitchAntigravity)
        XCTAssertFalse(settings.syncOpencodeAntigravityAuth)
    }

    func testDecodeSettingsWithoutAntigravityLaunchSettingDefaultsToOff() throws {
        var encoded = try JSONEncoder().encode(AppSettings.defaultValue)
        var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        object.removeValue(forKey: "launchAntigravityAfterSwitch")
        encoded = try JSONSerialization.data(withJSONObject: object)

        let settings = try JSONDecoder().decode(AppSettings.self, from: encoded)

        XCTAssertFalse(settings.launchAntigravityAfterSwitch)
        XCTAssertFalse(settings.autoSmartSwitchAntigravity)
    }

    func testQuotaVisibilityRoundTripsIndependently() throws {
        var settings = AppSettings.defaultValue
        settings.quotaVisibility.setVisible(false, for: UsageQuotaVisibilityKey.codexOneWeek)

        let restored = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(settings)
        )

        XCTAssertFalse(restored.quotaVisibility.isVisible(UsageQuotaVisibilityKey.codexOneWeek))
        XCTAssertTrue(restored.quotaVisibility.isVisible(UsageQuotaVisibilityKey.codexFiveHour))
    }
}
