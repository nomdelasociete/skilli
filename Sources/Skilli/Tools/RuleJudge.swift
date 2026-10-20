import Foundation
import SkilliCore

/// The user's rules (Settings → Ask → Your Rules), judged before an agent's
/// step: one Choice over the rules and "none" to TypeSafe Jev, else OpenAI
/// Decisions, in the same request style as `AskRouter`. Only the rules, the
/// tool's name and what it does, who asks and its arguments in short
/// (`ToolCallSummary`: no secrets, cut short) are sent. The same call is
/// not sent again for a few minutes. `ApprovalRules` says what wins.
@MainActor
final class RuleJudge {
    /// The user's decision keys, TypeSafe first (`AskRouter.keys`).
    var keys: @MainActor () -> [DecisionProvider: String]
    /// Self-test hook: requests sent so far.
    private(set) var requests = 0
    /// Self-test hook: the last call judged and what came of it.
    private(set) var last: (call: ApprovalRules.Call, verdict: ApprovalRules.Verdict, label: String)?

    private var kept: [String: (verdict: ApprovalRules.Verdict, at: ContinuousClock.Instant)] = [:]
    /// How long a verdict stands for the same call and rules.
    static let remembered: Duration = .seconds(300)
    /// An agent waits on it: a slow answer counts as none.
    static let timeout: TimeInterval = 5

    init(keys: @escaping @MainActor () -> [DecisionProvider: String]) {
        self.keys = keys
    }

    /// A key can check the rules.
    var canJudge: Bool { !keys().isEmpty }

    /// Which rule `call` falls under; `.unchecked` when no provider answered.
    func judge(_ call: ApprovalRules.Call, rules: [ApprovalRule]) async -> ApprovalRules.Verdict {
        let rules = ApprovalRules.active(rules)
        let keys = keys()
        guard !rules.isEmpty, !keys.isEmpty else { return .none }
        let now = ContinuousClock.now
        kept = kept.filter { now - $0.value.at < Self.remembered }
        let id = Self.id(call, rules)
        if let verdict = kept[id]?.verdict { return verdict }
        var failed: [String] = []
        for provider in [DecisionProvider.typeSafe, .openAI] {
            guard let key = keys[provider] else { continue }
            requests += 1
            do {
                let (verdict, label) = try await Self.judge(call, rules: rules, provider: provider, key: key)
                kept[id] = (verdict, .now)
                last = (call, verdict, label)
                return verdict
            } catch {
                failed.append(provider.title)
                Log.actions.error("Rules not checked by \(provider.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        let verdict = ApprovalRules.Verdict.unchecked("\(failed.joined(separator: " and ")) did not answer")
        last = (call, verdict, "")
        return verdict
    }

    /// One request to `provider`: the verdict and who gave it ("Jev · 0.21 s").
    static func judge(_ call: ApprovalRules.Call, rules: [ApprovalRule], provider: DecisionProvider,
                      key: String) async throws -> (ApprovalRules.Verdict, String) {
        let rules = ApprovalRules.active(rules)
        let question = DecisionQuestion(name: ApprovalRules.questionName, instructions: ApprovalRules.instructions,
                                        options: ApprovalRules.options(rules).map { .init(value: $0.value, description: $0.description) })
        let start = ContinuousClock.now
        let answer = try await DecisionClient.decide(question, input: call.state, provider: provider, key: key)
        let elapsed = ContinuousClock.now - start
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let verdict = ApprovalRules.verdict(choice: answer.choice, confidence: answer.confidence, probabilities: answer.probabilities,
                                            rules: rules)
        let name = provider == .typeSafe ? "Jev" : "Decisions"
        let top = answer.probabilities.sorted { $0.value > $1.value }.prefix(4).map { "\($0.key) \(Int($0.value * 100))%" }
        Log.trace("Rules for \(call.tool) (\(call.arguments)): \(answer.choice) \(Int(answer.confidence * 100))%, \(top.joined(separator: ", ")) → \(verdict)")
        Log.actions.notice("Rules checked for \(call.tool, privacy: .public) by \(name, privacy: .public) in \(String(format: "%.2f", seconds), privacy: .public) s")
        return (verdict, "\(name) · \(String(format: "%.2f s", seconds))")
    }

    /// The same call with the same rules: the tool, its server, what it
    /// sends in short, each rule's words and effect.
    private static func id(_ call: ApprovalRules.Call, _ rules: [ApprovalRule]) -> String {
        ([call.server ?? "", call.tool, call.arguments] + rules.map { "\($0.effect.rawValue):\($0.said)" }).joined(separator: "\u{1F}")
    }
}
