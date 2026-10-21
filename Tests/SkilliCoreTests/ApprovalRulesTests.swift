@testable import SkilliCore
import XCTest

final class ApprovalRulesTests: XCTestCase {
    private let allowRead = ApprovalRule(id: "a", text: "Reading my clipboard is fine.", effect: .allow)
    private let askSend = ApprovalRule(id: "b", text: "Ask before anything that sends a message", effect: .ask)
    private let neverDelete = ApprovalRule(id: "c", text: "Never delete files", effect: .never)

    private func decide(_ verdict: ApprovalRules.Verdict, risk: ToolRisk = .changes, mode: ApprovalMode = .auto,
                        override: ToolOverride? = nil, everyTime: Bool = false, strict: Bool = true) -> ToolPolicy.Ruled {
        ToolPolicy.decision(risk: risk, mode: mode, override: override, everyTime: everyTime, verdict: verdict, hasStrictRules: strict)
    }

    // MARK: - Precedence

    func testBlockComesFirstAndNoRuleAllowsIt() {
        let ruled = decide(.rule(allowRead, probability: 0.99), override: .never)
        XCTAssertEqual(ruled.decision, .block)
        XCTAssertNil(ruled.reason, "blocked by the user's right, not by a rule")
    }

    func testSettingsChangesAskWhateverTheRules() {
        for verdict in [ApprovalRules.Verdict.rule(allowRead, probability: 0.99), .rule(neverDelete, probability: 0.99), .none] {
            for mode in ApprovalMode.allCases {
                for override in [nil, ToolOverride.always, .ask] {
                    let ruled = decide(verdict, mode: mode, override: override, everyTime: true)
                    XCTAssertEqual(ruled.decision, .ask, "\(verdict) \(mode) \(String(describing: override))")
                    XCTAssertNil(ruled.reason, "a settings change is never put to the rules")
                }
            }
        }
        XCTAssertEqual(decide(.rule(allowRead, probability: 1), override: .never, everyTime: true).decision, .block, "only Block applies")
    }

    func testNeverRefusesWhenSureAndAsksWhenNot() {
        let sure = decide(.rule(neverDelete, probability: 0.8), mode: .always, override: .always)
        XCTAssertEqual(sure, ToolPolicy.Ruled(.block, .rule(neverDelete)))
        XCTAssertEqual(sure.reason?.line, "Refused by your rule: Never delete files")
        let unsure = decide(.rule(neverDelete, probability: 0.3), mode: .always)
        XCTAssertEqual(unsure, ToolPolicy.Ruled(.ask, .mayFallUnder(neverDelete)))
        XCTAssertEqual(unsure.reason?.line, "Asked because it may fall under your rule: Never delete files")
    }

    func testAskFirstBeatsAlwaysAllowAndAnAllowRight() {
        for override in [nil, ToolOverride.always] {
            let ruled = decide(.rule(askSend, probability: 0.7), risk: .read, mode: .always, override: override)
            XCTAssertEqual(ruled, ToolPolicy.Ruled(.ask, .rule(askSend)))
        }
        XCTAssertEqual(ToolPolicy.Reason.rule(askSend).line, "Asked because of your rule: Ask before anything that sends a message")
    }

    func testAllowLiftsTheModeButNotAlwaysAsk() {
        let lifted = decide(.rule(allowRead, probability: 0.9), risk: .read, mode: .ask)
        XCTAssertEqual(lifted, ToolPolicy.Ruled(.run, .rule(allowRead)))
        XCTAssertEqual(lifted.reason?.line, "Allowed by your rule: Reading my clipboard is fine")
        XCTAssertEqual(decide(.rule(allowRead, probability: 0.9), risk: .changes, mode: .auto).decision, .run)
        // The tool set to Always Ask by name stays so.
        XCTAssertEqual(decide(.rule(allowRead, probability: 0.9), risk: .read, mode: .always, override: .ask), ToolPolicy.Ruled(.ask))
        // Already running: the rule is not what let it run.
        XCTAssertEqual(decide(.rule(allowRead, probability: 0.9), risk: .read, mode: .always), ToolPolicy.Ruled(.run))
    }

    func testNoRuleLeavesTheRightAndTheModeAsBefore() {
        for risk in [ToolRisk.read, .harmless, .changes] {
            for mode in ApprovalMode.allCases {
                for override in [nil, ToolOverride.ask, .always, .never] {
                    XCTAssertEqual(decide(.none, risk: risk, mode: mode, override: override).decision,
                                   ToolPolicy.decision(risk: risk, mode: mode, override: override), "\(risk) \(mode)")
                }
            }
        }
        XCTAssertEqual(decide(.rule(neverDelete, probability: 1), risk: .none).decision, .run, "talking to the user is never judged")
    }

    func testRulesThatCannotBeCheckedMakeWhatWouldRunAsk() {
        let ruled = decide(.unchecked("TypeSafe Jev did not answer"), risk: .read, mode: .always)
        XCTAssertEqual(ruled, ToolPolicy.Ruled(.ask, .unchecked("TypeSafe Jev did not answer")))
        XCTAssertEqual(ruled.reason?.line, "Asked because your rules could not be checked: TypeSafe Jev did not answer")
        // Only Allow rules: nothing stricter was missed.
        XCTAssertEqual(decide(.unchecked("x"), risk: .read, mode: .always, strict: false), ToolPolicy.Ruled(.run))
        XCTAssertEqual(decide(.unchecked("x"), risk: .changes, mode: .auto), ToolPolicy.Ruled(.ask))
    }

    // MARK: - When to judge

    func testJudgedOnlyWhenARuleCouldChangeSomething() {
        let all = [allowRead, askSend, neverDelete]
        XCTAssertFalse(ApprovalRules.shouldJudge([], risk: .changes, mode: .ask, override: nil, everyTime: false))
        XCTAssertFalse(ApprovalRules.shouldJudge([ApprovalRule(text: "  ", effect: .never)], risk: .changes, mode: .ask, override: nil,
                                                 everyTime: false), "a rule without words")
        XCTAssertFalse(ApprovalRules.shouldJudge(all, risk: .changes, mode: .always, override: .never, everyTime: false), "blocked")
        XCTAssertFalse(ApprovalRules.shouldJudge(all, risk: .none, mode: .ask, override: nil, everyTime: false), "talks to the user")
        XCTAssertFalse(ApprovalRules.shouldJudge(all, risk: .changes, mode: .ask, override: nil, everyTime: true), "a settings change")
        // Runs now: only a strict rule can change that.
        XCTAssertFalse(ApprovalRules.shouldJudge([allowRead], risk: .read, mode: .always, override: nil, everyTime: false))
        XCTAssertTrue(ApprovalRules.shouldJudge([askSend], risk: .read, mode: .always, override: nil, everyTime: false))
        // Asks now: an Allow rule could let it run, not past Always Ask.
        XCTAssertTrue(ApprovalRules.shouldJudge([allowRead], risk: .read, mode: .ask, override: nil, everyTime: false))
        XCTAssertFalse(ApprovalRules.shouldJudge([allowRead], risk: .read, mode: .always, override: .ask, everyTime: false))
        XCTAssertTrue(ApprovalRules.shouldJudge([neverDelete], risk: .read, mode: .always, override: .ask, everyTime: false))
    }

    // MARK: - The answer

    func testVerdictPutsStrictRulesFirst() {
        let rules = [allowRead, askSend, neverDelete]
        XCTAssertEqual(ApprovalRules.options(rules).map(\.value), ["rule0", "rule1", "rule2", "none"])
        XCTAssertEqual(ApprovalRules.options(rules).first?.description, "Reading my clipboard is fine")
        // The model picks Allow, but Ask First is likely enough.
        XCTAssertEqual(ApprovalRules.verdict(choice: "rule0", confidence: 0.6, probabilities: ["rule0": 0.6, "rule1": 0.3, "none": 0.1], rules: rules),
                       .rule(askSend, probability: 0.3))
        // A sure Never wins over a likelier Ask First.
        XCTAssertEqual(ApprovalRules.verdict(choice: "rule1", confidence: 0.4, probabilities: ["rule1": 0.4, "rule2": 0.5], rules: rules),
                       .rule(neverDelete, probability: 0.5))
        // An unsure Never under a likelier Ask First: the likelier one.
        XCTAssertEqual(ApprovalRules.verdict(choice: "rule1", confidence: 0.6, probabilities: ["rule1": 0.6, "rule2": 0.3], rules: rules),
                       .rule(askSend, probability: 0.6))
        // Allow only when chosen and sure.
        XCTAssertEqual(ApprovalRules.verdict(choice: "rule0", confidence: 0.9, probabilities: ["rule0": 0.9, "none": 0.1], rules: rules),
                       .rule(allowRead, probability: 0.9))
        XCTAssertEqual(ApprovalRules.verdict(choice: "rule0", confidence: 0.45, probabilities: ["rule0": 0.45, "none": 0.4], rules: rules), .none)
        XCTAssertEqual(ApprovalRules.verdict(choice: "none", confidence: 0.8, probabilities: ["rule0": 0.15, "none": 0.8], rules: rules), .none)
        // No probabilities: the choice's confidence stands in.
        XCTAssertEqual(ApprovalRules.verdict(choice: "rule0", confidence: 0.92, probabilities: [:], rules: rules), .rule(allowRead, probability: 0.92))
    }

    func testRulesWithoutWordsAreLeftOutOfTheQuestion() {
        let rules = [ApprovalRule(text: "", effect: .never), askSend]
        XCTAssertEqual(ApprovalRules.options(rules).map(\.description), ["Ask before anything that sends a message", "No rule is about this call"])
        XCTAssertEqual(ApprovalRules.verdict(choice: "rule0", confidence: 0.9, probabilities: [:], rules: rules), .rule(askSend, probability: 0.9))
    }

    func testSuggestionsAreOneOfEach() {
        XCTAssertEqual(ApprovalRules.suggestions.map(\.effect), [.allow, .ask, .never])
        XCTAssertEqual(ApprovalRule.Effect.allCases.map(\.title), ["Allow", "Ask First", "Never"])
    }

    func testTheStateNamesTheToolAndKeepsServersWordsAsData() {
        let call = ApprovalRules.Call(tool: "send_email", description: String(repeating: "Sends an email. ", count: 30), kind: "changes things",
                                      server: "gmail", caller: "Claude Code", arguments: "to: “paul@example.com”")
        let state = call.state
        XCTAssertTrue(state.contains("Tool: send_email, a tool of the connected service “gmail”"), state)
        XCTAssertTrue(state.contains("What it does, as the service says: Sends an email."), state)
        XCTAssertTrue(state.contains("It changes things\nAsked by: Claude Code\nArguments: to: “paul@example.com”"), state)
        XCTAssertLessThan(state.count, 600, "the description is cut")
        let own = ApprovalRules.Call(tool: "get_clipboard", title: "Read the clipboard", description: "Returns the clipboard's text.",
                                     kind: "reads", caller: "Ask", arguments: "none")
        XCTAssertTrue(own.state.contains("Tool: Read the clipboard (get_clipboard), one of skil.li's own tools"), own.state)
    }

    // MARK: - Arguments in short

    func testArgumentsKeepNoSecret() {
        let summary = ToolCallSummary.arguments([
            "to": "Thomas",
            "password": "hunter2",
            "apiKey": "abc",
            "X-Api-Key": "abc",
            "client_secret": "abc",
            "authorization": "whatever",
            "note": "sk-ant-api03-AAAAAAAAAAAAAAAAAAAA",
            "github": "ghp_0123456789abcdefABCDEF0123456789abcd",
            "jwt": "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abc",
            "card": "4111 1111 1111 1111",
            "iban": "FR7630006000011234567890189",
            "account": "FR76 3000 6000 0112 3456 7890 189",
            "blob": "aB3dE5gH7jK9mN1pQ3sT5vX7zA9cE1gI3kM5",
            "link": "https://example.com/reset?token=abc123&user=me#x"
        ])
        for secret in ["hunter2", "abc", "whatever", "sk-ant", "ghp_", "eyJ", "4111", "FR76", "aB3dE5", "token=", "abc123"] {
            XCTAssertFalse(summary.contains(secret), "\(secret) in \(summary)")
        }
        XCTAssertTrue(summary.contains("to: “Thomas”"), summary)
        XCTAssertTrue(summary.contains("password: (hidden)"), summary)
        XCTAssertTrue(summary.contains("link: “https://example.com/reset?…”"), summary)
    }

    func testOrdinaryValuesStay() {
        let summary = ToolCallSummary.arguments(["keys": "cmd+s", "max_tokens": 200, "author": "Paul", "cask": true, "phone": "+33 6 12 34 56 78",
                                                 "id": "3f2a1b4c-9d8e-4f7a-b6c5-d4e3f2a1b0c9", "path": "/Users/me/Documents/Rapport annuel 2026.pdf"])
        XCTAssertEqual(summary, "author: “Paul”, cask: true, id: “3f2a1b4c-9d8e-4f7a-b6c5-d4e3f2a1b0c9”, keys: “cmd+s”, max_tokens: 200, "
            + "path: “/Users/me/Documents/Rapport annuel 2026.pdf”, phone: “+33 6 12 34 56 78”")
        XCTAssertEqual(ToolCallSummary.arguments([:]), "none")
    }

    func testArgumentsAreCutShort() {
        let long = String(repeating: "word ", count: 200)
        let one = ToolCallSummary.arguments(["text": long])
        XCTAssertLessThanOrEqual(one.count, "text: “”".count + ToolCallSummary.valueLimit)
        XCTAssertTrue(one.hasSuffix("…”"), one)
        let many = ToolCallSummary.arguments(Dictionary(uniqueKeysWithValues: (0..<40).map { ("field\($0)", "value number \($0)") }))
        XCTAssertEqual(many.count, ToolCallSummary.limit)
        XCTAssertTrue(many.hasSuffix("…"))
        let lines = ToolCallSummary.arguments(["text": "first line\nsecond line"])
        XCTAssertEqual(lines, "text: “first line second line”")
    }

    func testNestedArgumentsAreShortToo() {
        let summary = ToolCallSummary.arguments([
            "recipients": ["a@example.com", "b@example.com", "c@example.com", "d@example.com", "e@example.com"],
            "options": ["silent": false, "token": "zzz", "deep": ["deeper": ["deepest": 1]]] as [String: Any]
        ])
        XCTAssertEqual(summary, "options: {deep: {deeper: {…}}, silent: false, token: (hidden)}, "
            + "recipients: [“a@example.com”, “b@example.com”, “c@example.com” and 2 more]")
    }

    func testSecretNamesByTheirWords() {
        for name in ["password", "userPassword", "api_key", "apiKey", "X-Api-Key", "access_token", "refreshToken", "Authorization",
                     "client_secret", "privateKey", "cvv", "otp_code"] {
            XCTAssertTrue(ToolCallSummary.isSecretName(name), name)
        }
        for name in ["keys", "key_code", "author", "tokens_used", "max_tokens", "title", "pinned", "keyword"] {
            XCTAssertFalse(ToolCallSummary.isSecretName(name), name)
        }
    }
}
