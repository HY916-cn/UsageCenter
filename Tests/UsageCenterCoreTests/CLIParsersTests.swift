import Foundation
import XCTest
@testable import UsageCenterCore

final class CLIParsersTests: XCTestCase {
    func testClaudeJSONUsageParsing() throws {
        let sampleJSON = """
        {
          "is_error": false,
          "result": "You are currently using your subscription to power your Claude Code usage\\n\\nCurrent session: 14% used · resets Nov 25 at 4:30am (Asia/Shanghai)\\nCurrent week (all models): 32% used · resets Nov 28 at 10pm (Asia/Shanghai)"
        }
        """
        let ref = ISO8601DateFormatter().date(from: "2026-11-24T15:30:00Z")!
        let auth = ClaudeCLIParser.AuthInfo(loggedIn: true, subscriptionType: "pro", authMethod: "claude.ai")
        let snapshot = try ClaudeCLIParser.parseUsageOutput(Data(sampleJSON.utf8), authInfo: auth, referenceDate: ref)

        XCTAssertEqual(snapshot.provider, .claude)
        XCTAssertEqual(snapshot.accountLabel, "Claude Pro")
        XCTAssertEqual(snapshot.windows.count, 2)

        let pair = snapshot.resolvedWindows(antigravityGroup: .auto)
        XCTAssertEqual(pair.fiveHour?.usedPercent, 14)
        XCTAssertEqual(pair.fiveHour?.remainingPercent, 86)
        XCTAssertNotNil(pair.fiveHour?.resetsAt)

        XCTAssertEqual(pair.weekly?.usedPercent, 32)
        XCTAssertEqual(pair.weekly?.remainingPercent, 68)
        XCTAssertNotNil(pair.weekly?.resetsAt)
    }

    func testCodexRateLimitsParsing() throws {
        let account: [String: Any] = [
            "account": [
                "type": "chatgpt",
                "planType": "plus"
            ]
        ]
        let rateLimits: [String: Any] = [
            "rateLimitsByLimitId": [
                "codex": [
                    "limitId": "codex",
                    "primary": [
                        "usedPercent": 6,
                        "windowDurationMins": 300,
                        "resetsAt": 1_795_551_747
                    ],
                    "secondary": [
                        "usedPercent": 16,
                        "windowDurationMins": 10_080,
                        "resetsAt": 1_795_690_346
                    ]
                ]
            ]
        ]

        let snapshot = try CodexCLIParser.parse(accountResult: account, rateLimitsResult: rateLimits)
        XCTAssertEqual(snapshot.accountLabel, "ChatGPT Plus")
        let pair = snapshot.resolvedWindows(antigravityGroup: .auto)
        XCTAssertEqual(pair.fiveHour?.usedPercent, 6)
        XCTAssertEqual(pair.fiveHour?.remainingPercent, 94)
        XCTAssertEqual(pair.weekly?.usedPercent, 16)
        XCTAssertEqual(pair.weekly?.remainingPercent, 84)
    }

    func testAntigravityJSONParsingAndGroupFiltering() throws {
        let sample = """
        {
          "status": "SUCCESS",
          "command": {
            "name": "usage",
            "data": {
              "groups": [
                {
                  "name": "Gemini Models",
                  "buckets": [
                    { "id": "gemini-weekly", "window": "weekly", "remaining_fraction": 0.98, "reset_time": "2026-12-01T15:22:25Z" },
                    { "id": "gemini-5h", "window": "5h", "remaining_fraction": 0.92, "reset_time": "2026-11-24T20:22:25Z" }
                  ]
                },
                {
                  "name": "Claude and GPT models",
                  "buckets": [
                    { "id": "3p-weekly", "window": "weekly", "remaining_fraction": 1.0, "reset_time": "2026-12-01T15:39:16Z" },
                    { "id": "3p-5h", "window": "5h", "remaining_fraction": 1.0, "reset_time": "2026-11-24T20:39:16Z" }
                  ]
                }
              ]
            }
          }
        }
        """
        let snapshot = try AntigravityCLIParser.parseUsageOutput(Data(sample.utf8))
        XCTAssertEqual(snapshot.windows.count, 4)

        let autoPair = snapshot.resolvedWindows(antigravityGroup: .auto)
        XCTAssertEqual(autoPair.fiveHour?.usedPercent, 8)
        XCTAssertEqual(autoPair.weekly?.usedPercent, 2)

        let thirdPartyPair = snapshot.resolvedWindows(antigravityGroup: .thirdParty)
        XCTAssertEqual(thirdPartyPair.fiveHour?.usedPercent, 0)
        XCTAssertEqual(thirdPartyPair.weekly?.usedPercent, 0)
    }

    func testDeepSeekBalanceJSONParsing() throws {
        let sample = """
        {
          "is_available": true,
          "balance_infos": [
            {
              "currency": "CNY",
              "total_balance": "48.60",
              "granted_balance": "8.60",
              "topped_up_balance": "40.00"
            },
            {
              "currency": "USD",
              "total_balance": "0.00",
              "granted_balance": "0.00",
              "topped_up_balance": "0.00"
            }
          ]
        }
        """
        let snapshot = try DeepSeekCLIParser.parseBalanceOutput(Data(sample.utf8))
        XCTAssertEqual(snapshot.isAvailable, true)
        let preferred = snapshot.preferredBalance(currencyPreference: "AUTO")
        XCTAssertEqual(preferred?.currency, "CNY")
        XCTAssertEqual(preferred?.formattedTotal, "¥48.60")
        XCTAssertEqual(preferred?.toppedUpBalance, "40.00")
        XCTAssertEqual(preferred?.grantedBalance, "8.60")
    }
}
