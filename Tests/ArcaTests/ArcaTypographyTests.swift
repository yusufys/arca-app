import XCTest
import SwiftUI
import CoreText
@testable import ArcaUI

final class ArcaTypographyTests: XCTestCase {
    func testBundledFacesRegisterWithArabicGlyphs() {
        XCTAssertEqual(ArcaTypography.registeredArabicFaces.count, 4)
        for name in ArcaTypography.registeredArabicFaces {
            let font = CTFontCreateWithName(name as CFString, 17, nil)
            XCTAssertEqual(CTFontCopyPostScriptName(font) as String, name)
            var characters = Array("العربية".utf16)
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            XCTAssertTrue(CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count))
            XCTAssertFalse(glyphs.contains(0), "Missing Arabic glyph in \(name)")
        }
    }

    func testTypefaceIsRestrictedToArabicAndPreservesSemanticWeight() {
        for locale in ["en", "en_US", "tr", "tr_TR"] {
            XCTAssertNil(ArcaTypography.arabicFace(locale: Locale(identifier: locale), style: .body, weight: nil, boldText: false))
        }
        XCTAssertEqual(ArcaTypography.arabicFace(locale: Locale(identifier: "ar_SA"), style: .body, weight: nil, boldText: false), "IBMPlexSansArabic")
        XCTAssertEqual(ArcaTypography.arabicFace(locale: Locale(identifier: "ar"), style: .headline, weight: nil, boldText: false), "IBMPlexSansArabic-SmBld")
        XCTAssertEqual(ArcaTypography.arabicFace(locale: Locale(identifier: "ar"), style: .body, weight: .bold, boldText: false), "IBMPlexSansArabic-Bold")
        XCTAssertEqual(ArcaTypography.arabicFace(locale: Locale(identifier: "ar"), style: .body, weight: nil, boldText: true), "IBMPlexSansArabic-SmBld")
    }
}
