import Foundation
import XCTest
@testable import UsageCenterCore

final class CLIParsersTests: XCTestCase {
    func testClaudeRemainingQuotaParsing() throws {
        let sampleJSON = """
        {
          "is_error": false,
          "result": "Current session: 14% used · resets Nov 25 at 4:30am (Asia/Shanghai)\\nCurrent week (all models): 32% used · resets Nov 28 at 10pm (Asia/Shanghai)"
        }
        """
        let ref = ISO8601DateFormatter().date(from: "2026-11-24T15:30:00Z")!
        let auth = ClaudeCLIParser.AuthInfo(loggedIn: true, subscriptionType: "pro", authMethod: "claude.ai")
        let snapshot = try ClaudeCLIParser.parseUsageOutput(Data(sampleJSON.utf8), authInfo: auth, referenceDate: ref)

        let pair = snapshot.resolvedWindows(antigravityGroup: .auto)
        XCTAssertEqual(pair.fiveHour?.remainingPercent, 86)
        XCTAssertEqual(pair.weekly?.remainingPercent, 68)
    }

    func testDSHAccountWalletSummaryParsing() throws {
        let sample = """
        {
          "code": 0,
          "data": {
            "biz_code": 0,
            "biz_data": {
              "normal_wallets": [{ "currency": "CNY", "balance": "36.4416089000000000" }],
              "bonus_wallets": [{ "currency": "CNY", "balance": "2.00" }],
              "total_costs": [{ "currency": "CNY", "amount": "37.8409135400000000" }]
            }
          }
        }
        """
        let snapshot = try DeepSeekCLIParser.parseBalanceOutput(Data(sample.utf8))
        let item = snapshot.preferredBalance(currencyPreference: "AUTO")
        XCTAssertEqual(item?.formattedTotal, "¥38.44")
        XCTAssertEqual(item?.formattedToppedUp, "¥36.44")
        XCTAssertEqual(item?.formattedGranted, "¥2.00")
        XCTAssertEqual(item?.formattedTotalCost, "¥37.84")
    }
}
