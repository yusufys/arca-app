import XCTest
import ArcaCore
@testable import ArcaUI

final class LocalizationTests: XCTestCase {
    func testNativeCatalogLanguageSwitchAndArabicPluralRules() {
        XCTAssertEqual(AppLanguage.arabic.localized("Email"), "البريد الإلكتروني")
        XCTAssertEqual(AppLanguage.turkish.localized("Email"), "E-posta")
        XCTAssertEqual(AppLanguage.english.localized("Email"), "Email")
        XCTAssertEqual(AppLanguage.arabic.format("count.fields", 1), "حقل واحد")
        XCTAssertEqual(AppLanguage.arabic.format("count.fields", 2), "حقلان")
        XCTAssertTrue(AppLanguage.arabic.format("count.fields", 11).contains("حقلاً"))
        XCTAssertEqual(AppLanguage.english.format("count.collections", 1), "1 Collection")
        XCTAssertEqual(AppLanguage.english.format("count.collections", 4), "4 Collections")
        XCTAssertEqual(AppLanguage.arabic.format("count.collections", 1), "مجموعة واحدة")
        XCTAssertEqual(AppLanguage.arabic.format("count.collections", 2), "مجموعتان")
        XCTAssertEqual(AppLanguage.turkish.format("count.collections", 4), "4 Koleksiyon")
        XCTAssertEqual(ArcaStrings.text("tab.home", language: .turkish), "Ana Sayfa")
    }

    func testRecordValuesAndValidationUseTheSelectedLocale() {
        XCTAssertEqual(FieldValue.boolean(true).plainTextSummary(locale: AppLanguage.arabic.locale), "نعم")
        XCTAssertEqual(FieldValue.boolean(false).plainTextSummary(locale: AppLanguage.turkish.locale), "Hayır")
        let field = FieldDefinition(label: "User label", type: .shortText, isRequired: true)
        let schema = CollectionSchema(spaceId: UUID(), name: "User collection", fields: [field])
        let errors = SchemaEngine.validate(values: [:], against: schema, locale: AppLanguage.arabic.locale)
        XCTAssertEqual(errors.first?.fieldLabel, "User label")
        XCTAssertEqual(errors.first?.reason, "هذا الحقل مطلوب.")
        XCTAssertEqual(FieldValue.shortText("User content").plainTextSummary(locale: AppLanguage.arabic.locale), "User content")
    }

    func testCatalogTranslatesSchemaAndOptionsWithFallbackForNewTemplates() throws {
        let document: [String: Any] = ["version": 1, "templates": [[
            "id": "new-template", "subtitle": "Default description",
            "schema": ["name": "Equipment", "fields": [["label": "Kind", "type": "single_select", "options": ["New", "Used"]]]],
            "localizations": ["ar": ["subtitle": "معدات المنزل", "schema": [
                "name": "معدات", "fields": [["label": "الحالة", "type": "single_select", "options": ["جديد", "مستعمل"]]]
            ]]]
        ]]]
        let data = try JSONSerialization.data(withJSONObject: document)
        let arabic = try XCTUnwrap(CollectionCatalogClient.templates(in: data, language: .arabic).first)
        XCTAssertEqual(arabic.name, "معدات")
        XCTAssertEqual(arabic.fields[0].options.map(\.label), ["جديد", "مستعمل"])
        XCTAssertEqual(try CollectionCatalogClient.templates(in: data, language: .turkish).first?.name, "Equipment")
        let copy = arabic.instantiateSchema(for: UUID())
        _ = try CollectionCatalogClient.templates(in: data, language: .english)
        XCTAssertEqual(copy.name, "معدات", "Changing UI language must never rewrite saved user collections")
    }

    func testEveryCatalogEntryHasAllSupportedTranslations() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: repo.appendingPathComponent("Sources/ArcaUI/Resources/Localizable.xcstrings"))
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try XCTUnwrap(catalog["strings"] as? [String: [String: Any]])
        for (key, entry) in entries {
            let locales = try XCTUnwrap(entry["localizations"] as? [String: Any], key)
            for language in AppLanguage.allCases { XCTAssertNotNil(locales[language.rawValue], "Missing \(language.rawValue): \(key)") }
        }
    }
}
