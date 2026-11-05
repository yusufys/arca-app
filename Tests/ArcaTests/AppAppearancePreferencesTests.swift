import XCTest
import ArcaCore
@testable import ArcaUI

final class AppAppearancePreferencesTests: XCTestCase {
    func testDefaultOptionIsForestEmeraldAndAllSixColorsMatchSpecification() {
        XCTAssertEqual(AppAccentColorOption.defaultOption, .forestEmerald)
        XCTAssertEqual(AppAccentColorOption.allCases.count, 6)
        XCTAssertEqual(
            AppAccentColorOption.allCases.map(\.rawValue),
            ["#1F5D3F", "#1E3A8A", "#7C2D12", "#581C87", "#18181B", "#0F3F2A"]
        )
    }

    func testNormalizedHexAndSafeFallbackForInvalidOrUnknownValues() {
        XCTAssertEqual(AppAccentColorOption.normalizedHex("  1e3a8a "), "#1E3A8A")
        XCTAssertEqual(AppAccentColorOption.normalizedHex("#581c87"), "#581C87")
        XCTAssertEqual(AppAccentColorOption.resolve(from: "7c2d12"), .terracottaClay)
        XCTAssertEqual(AppAccentColorOption.resolve(from: "#0F3F2A"), .deepPine)
        XCTAssertEqual(AppAccentColorOption.resolve(from: nil), .forestEmerald)
        XCTAssertEqual(AppAccentColorOption.resolve(from: ""), .forestEmerald)
        XCTAssertEqual(AppAccentColorOption.resolve(from: "#FFFFFF"), .forestEmerald)
        XCTAssertEqual(AppAccentColorOption.resolve(from: "not-a-hex"), .forestEmerald)
    }

    func testPersistenceStoreRoundTripAndReset() throws {
        let suiteName = "com.arca.tests.appearance.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppAppearancePreferencesStore(defaults: defaults)
        XCTAssertEqual(store.loadAccentColor(), .forestEmerald)
        XCTAssertEqual(store.loadAppearanceMode(), .light)

        for option in AppAccentColorOption.allCases {
            store.saveAccentColor(option)
            XCTAssertEqual(store.loadAccentColor(), option)
        }

        store.saveAppearanceMode(.dark)
        XCTAssertEqual(store.loadAppearanceMode(), .dark)

        // Corrupted raw value falls back safely to .forestEmerald / .light
        defaults.set("invalid", forKey: AppAppearancePreferencesStore.accentColorDefaultsKey)
        defaults.set("invalid", forKey: AppAppearancePreferencesStore.appearanceModeDefaultsKey)
        XCTAssertEqual(store.loadAccentColor(), .forestEmerald)
        XCTAssertEqual(store.loadAppearanceMode(), .light)

        store.saveAccentColor(.royalPlum)
        store.reset()
        XCTAssertEqual(store.loadAccentColor(), .forestEmerald)
    }

    func testAllAccentColorNamesAndTagsAreLocalizedInEnglishArabicAndTurkish() {
        for option in AppAccentColorOption.allCases {
            for language in AppLanguage.allCases {
                let localizedName = option.localizedName(in: language)
                let localizedTag = option.localizedTag(in: language)
                XCTAssertFalse(localizedName.isEmpty, "Empty name for \(option) in \(language)")
                XCTAssertFalse(localizedTag.isEmpty, "Empty tag for \(option) in \(language)")
            }
            XCTAssertNotEqual(option.localizedName(in: .english), option.localizedName(in: .arabic))
            XCTAssertNotEqual(option.localizedName(in: .english), option.localizedName(in: .turkish))
        }
    }
}
