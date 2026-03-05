import Foundation
import XCTest
@testable import iNote2ObsidianApp

final class AppLocalizationTests: XCTestCase {
    func testLegacySettingsDecodeDefaultsLanguageToEnglish() throws {
        let json = """
        {
          "autoStartAtLogin" : true,
          "excludeRecentlyDeleted" : true,
          "lastRunMode" : "stopped",
          "outputRootPath" : "/tmp/iNote",
          "syncInterval" : "5m",
          "totalSyncRounds" : 12
        }
        """

        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.language, .english)
    }

    func testAllLocalizationKeysHaveValuesInBothLanguages() {
        let languages: [AppLanguage] = [.english, .simplifiedChinese]
        for language in languages {
            let localizer = AppLocalizer(language: language)
            for key in L10nKey.allCases {
                XCTAssertFalse(localizer.text(key).isEmpty, "Missing text for \(language.rawValue) \(key)")
            }
        }
    }
}
