import Foundation
import Testing
@testable import RemoteMic

/// 2026-09-24 把取名由 `chromecase` 更正为 `chromecast`，其中四个设置键落在 UserDefaults 上。
/// 改键名会让老用户的开关、语音模式与已放开的系统占用键全部回到默认值，所以加载前必须做一次性搬迁。
///
/// 这里的四个旧键名是**迁移输入**，不是可用键名。它们必须继续存在于代码里，
/// 直到确认不再有旧版本用户为止（回滚到旧版本也要能读回设置）。
@Suite("Chromecast settings key migration")
struct ChromecastSettingsMigrationTests {
    private static let legacyAllowSystemReservedKeys = "chromecase.allowSystemReservedKeys"
    private static let legacySystemReservedExceptions = "chromecase.systemReservedExceptions"
    private static let legacyEnabled = "chromecase.enabled"
    private static let legacyVoiceMode = "chromecase.voiceMode"

    private static let currentAllowSystemReservedKeys = "chromecast.allowSystemReservedKeys"
    private static let currentSystemReservedExceptions = "chromecast.systemReservedExceptions"
    private static let currentEnabled = "chromecast.enabled"
    private static let currentVoiceMode = "chromecast.voiceMode"

    private func isolatedDefaults(
        _ label: String,
        suiteName: inout String
    ) throws -> UserDefaults {
        suiteName = "ChromecastSettingsKeyMigrationTests.\(label).\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: suiteName))
    }

    @Test func legacyValuesAreCarriedOverToTheCorrectedKeys() throws {
        var suiteName = ""
        let defaults = try isolatedDefaults("carryOver", suiteName: &suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: Self.legacyAllowSystemReservedKeys)
        defaults.set("left,select", forKey: Self.legacySystemReservedExceptions)
        defaults.set(false, forKey: Self.legacyEnabled)
        defaults.set("hold", forKey: Self.legacyVoiceMode)

        let settings = AppSettings(defaults: defaults)

        #expect(settings.chromecastAllowSystemReservedKeys)
        #expect(settings.chromecastSystemReservedExceptions == ["left", "select"])
        #expect(settings.chromecastEnabled == false)
        #expect(settings.chromecastVoiceMode == .hold)
        // 值已落到新键上（初始化不触发 didSet，所以这里只可能是搬迁写的）。
        #expect(defaults.object(forKey: Self.currentEnabled) != nil)
        #expect(defaults.object(forKey: Self.currentVoiceMode) != nil)
        // 旧键保留：用户回滚到旧版本仍能读回同一份设置。
        #expect(defaults.object(forKey: Self.legacyEnabled) != nil)
        #expect(defaults.object(forKey: Self.legacyVoiceMode) != nil)
    }

    @Test func correctedKeysWinAndAreNeverOverwrittenByLegacyValues() throws {
        var suiteName = ""
        let defaults = try isolatedDefaults("currentWins", suiteName: &suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: Self.legacyEnabled)
        defaults.set("hold", forKey: Self.legacyVoiceMode)
        defaults.set(false, forKey: Self.legacyAllowSystemReservedKeys)
        defaults.set(true, forKey: Self.currentEnabled)
        defaults.set("toggle", forKey: Self.currentVoiceMode)
        defaults.set(true, forKey: Self.currentAllowSystemReservedKeys)

        let settings = AppSettings(defaults: defaults)

        // 用户在新版本里改过的值必须保留，不能被旧键的残留值覆盖。
        #expect(settings.chromecastEnabled)
        #expect(settings.chromecastVoiceMode == .toggle)
        #expect(settings.chromecastAllowSystemReservedKeys)
    }

    @Test func aFirstRunWritesNothingAndKeepsTheProductDefaults() throws {
        var suiteName = ""
        let defaults = try isolatedDefaults("firstRun", suiteName: &suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)

        #expect(settings.chromecastEnabled) // 首次运行默认开启
        #expect(settings.chromecastVoiceMode == ChromecastVoiceMode.productDefault)
        #expect(settings.chromecastSystemReservedExceptions.isEmpty)
        // 没有任何东西可搬时不得产生写入。
        #expect(defaults.object(forKey: Self.currentEnabled) == nil)
        #expect(defaults.object(forKey: Self.currentVoiceMode) == nil)
        #expect(defaults.object(forKey: Self.currentAllowSystemReservedKeys) == nil)
        #expect(defaults.object(forKey: Self.currentSystemReservedExceptions) == nil)
    }

    @Test func migratingTwiceIsIdempotent() throws {
        var suiteName = ""
        let defaults = try isolatedDefaults("idempotent", suiteName: &suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: Self.legacyEnabled)
        defaults.set("hold", forKey: Self.legacyVoiceMode)
        defaults.set(false, forKey: Self.currentEnabled)
        defaults.set("toggle", forKey: Self.currentVoiceMode)

        let first = AppSettings(defaults: defaults)
        // 第二次加载时新键已经存在，旧键不得再覆盖它。
        let second = AppSettings(defaults: defaults)

        #expect(first.chromecastEnabled == second.chromecastEnabled)
        #expect(first.chromecastVoiceMode == second.chromecastVoiceMode)
        #expect(second.chromecastEnabled == false)
        #expect(second.chromecastVoiceMode == .toggle)
    }
}
