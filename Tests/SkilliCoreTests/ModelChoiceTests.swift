import XCTest
@testable import SkilliCore

final class ModelChoiceTests: XCTestCase {
    func testFilesWrittenBeforeKeepTheirModel() {
        XCTAssertEqual(ModelChoice.parse(model: "haiku"), .choice(.claude("haiku")))
        XCTAssertEqual(ModelChoice.parse(model: "Sonnet"), .choice(.claude("sonnet")))
        XCTAssertEqual(ModelChoice.parse(model: nil), .standard)
        XCTAssertEqual(ModelChoice.parse(model: "default"), .standard)
        XCTAssertEqual(ModelChoice.parse(model: "opus"), .choice(.claude("opus")))
        XCTAssertEqual(ModelChoice.parse(model: "claude/opus"), .choice(.claude("opus")))
        // An effort means nothing for Claude.
        XCTAssertEqual(ModelChoice.parse(model: "haiku", effort: "high"), .choice(.claude("haiku")))

        let old = "---\ntitle: Fix\nmodel: haiku\n---\nFix this.\n\n{selection}\n"
        let file = PromptFile(parsing: old)
        XCTAssertEqual(file.model, "haiku")
        XCTAssertNil(file.effort)
        XCTAssertEqual(file.text, old)
    }

    func testOpenAIModelsWithTheirEffort() {
        XCTAssertEqual(ModelChoice.parse(model: "chatgpt/gpt-6-luna", effort: "low"),
                       .choice(ModelChoice(provider: .chatGPT, model: "gpt-6-luna", effort: .low)))
        XCTAssertEqual(ModelChoice.parse(model: "openai/gpt-6.1-sol", effort: "Medium"),
                       .choice(ModelChoice(provider: .openAI, model: "gpt-6.1-sol", effort: .medium)))
        // No effort, or one too slow for a card: low.
        XCTAssertEqual(ModelChoice.parse(model: "chatgpt/gpt-6-luna"), .choice(ModelChoice(provider: .chatGPT, model: "gpt-6-luna", effort: .low)))
        XCTAssertEqual(ModelChoice.parse(model: "chatgpt/gpt-6-luna", effort: "ultra"),
                       .choice(ModelChoice(provider: .chatGPT, model: "gpt-6-luna", effort: .low)))
    }

    func testUnknownModelsAreSaidNotRun() {
        XCTAssertEqual(ModelChoice.parse(model: "gemini/2.5-pro"), .unknown("gemini/2.5-pro"))
        XCTAssertEqual(ModelChoice.parse(model: "mistral"), .unknown("mistral"))
        XCTAssertEqual(ModelChoice.parse(model: "chatgpt/-rf"), .unknown("chatgpt/-rf"))
        XCTAssertEqual(ModelChoice.parse(model: "chatgpt/gpt 6"), .unknown("chatgpt/gpt 6"))
        XCTAssertEqual(ModelChoice.parse(model: "chatgpt/"), .unknown("chatgpt/"))
        XCTAssertFalse(ModelChoice.isModelID(String(repeating: "a", count: 65)))
        XCTAssertTrue(ModelChoice.isModelID("gpt-6.1-sol"))
    }

    func testFileRoundTrip() {
        let choice = ModelChoice(provider: .chatGPT, model: "gpt-6-luna", effort: .low)
        let file = PromptFile(title: "Spelling Grammar Custom", instruction: "Fix it.\n\n{selection}", model: choice.fileModel,
                              effort: choice.fileEffort, output: .replace)
        XCTAssertTrue(file.text.contains("model: chatgpt/gpt-6-luna\neffort: low\n"))
        let read = PromptFile(parsing: file.text)
        XCTAssertEqual(read, file)
        XCTAssertEqual(ModelChoice.parse(model: read.model, effort: read.effort), .choice(choice))
        // An effort without a model goes.
        XCTAssertNil(PromptFile(parsing: "---\neffort: high\n---\nHi").effort)
        // A model this build does not know stays as written.
        let newer = "---\nmodel: gemini/2.5-pro\neffort: low\n---\nHi\n"
        XCTAssertEqual(PromptFile(parsing: newer).text, newer)
    }

    func testIdentifiersAndTitles() {
        let luna = ModelChoice(provider: .chatGPT, model: "gpt-6-luna", effort: .low)
        XCTAssertEqual(luna.id, "chatgpt/gpt-6-luna@low")
        XCTAssertEqual(ModelChoice(id: luna.id), luna)
        XCTAssertEqual(ModelChoice(id: "claude/sonnet"), .claude("sonnet"))
        XCTAssertNil(ModelChoice(id: "claude/gpt"))
        XCTAssertEqual(luna.title, "GPT-6 Luna Low")
        XCTAssertEqual(luna.label, "ChatGPT · GPT-6 Luna Low")
        XCTAssertEqual(ModelChoice(provider: .openAI, model: "gpt-6.1-sol", effort: .high).label, "OpenAI API · GPT-6.1 Sol High")
        XCTAssertEqual(ModelChoice.claude("haiku").label, "Claude · Haiku")
        XCTAssertEqual(ModelChoice.modelTitle("o4-mini"), "O4 Mini")
        XCTAssertEqual(luna.with(effort: .high).effort, .high)
        XCTAssertNil(ModelChoice.claude("opus").with(effort: .high).effort)
    }

    func testCodexCatalog() throws {
        let json = """
        {"models": [
          {"slug": "gpt-6.1-sol", "visibility": "list", "supported_reasoning_levels": [{"effort": "low"}, {"effort": "medium"}, {"effort": "high"}, {"effort": "xhigh"}, {"effort": "ultra"}]},
          {"slug": "gpt-6-astra", "visibility": "list", "supported_reasoning_levels": [{"effort": "low"}, {"effort": "medium"}]},
          {"slug": "gpt-6-sol", "visibility": "list", "supported_reasoning_levels": [{"effort": "low"}]},
          {"slug": "gpt-6-luna", "visibility": "list", "supported_reasoning_levels": [{"effort": "low"}, {"effort": "medium"}, {"effort": "high"}]},
          {"slug": "gpt-reserve", "visibility": "hide", "supported_reasoning_levels": [{"effort": "low"}]},
          {"slug": "gpt-5.6-terra", "visibility": "list", "supported_reasoning_levels": [{"effort": "low"}]}
        ]}
        """
        let offers = try XCTUnwrap(ModelCatalog.codexModels(Data(json.utf8)))
        XCTAssertEqual(offers.map(\.id), ["gpt-6.1-sol", "gpt-6-astra", "gpt-6-sol", "gpt-6-luna", "gpt-5.6-terra"])
        XCTAssertEqual(offers[0].efforts, [.low, .medium, .high])
        XCTAssertEqual(offers[1].efforts, [.low, .medium])
        XCTAssertEqual(ModelCatalog.current(offers).map(\.id), ["gpt-6.1-sol", "gpt-6-astra", "gpt-6-luna"])
        XCTAssertNil(ModelCatalog.codexModels(Data("Error: not logged in".utf8)))
    }

    func testOpenAIModelList() throws {
        let ids = ["gpt-6-luna", "gpt-6-luna-2026-09-01", "gpt-6.1-sol", "gpt-6-sol", "gpt-6-astra", "gpt-realtime-6",
                   "gpt-6-luna-tts", "gpt-6-luna-transcribe", "gpt-image-2", "text-embedding-3-large", "dall-e-3", "gpt-5.6-terra",
                   "o4-mini", "gpt-6-codex", "gpt-6-chat-latest", "omni-moderation-latest", "gpt-6-luna-search-preview"]
        let body = try JSONSerialization.data(withJSONObject: ["object": "list", "data": ids.map { ["id": $0, "object": "model"] }])
        let offers = try XCTUnwrap(ModelCatalog.openAIModels(body))
        XCTAssertEqual(offers.map(\.id), ["gpt-6.1-sol", "gpt-6-astra", "gpt-6-luna", "gpt-6-sol", "gpt-5.6-terra"])
        XCTAssertEqual(ModelCatalog.current(offers).map(\.id), ["gpt-6.1-sol", "gpt-6-astra", "gpt-6-luna"])
        XCTAssertTrue(offers.allSatisfy { $0.efforts == ReasoningEffort.allCases })
        XCTAssertNil(ModelCatalog.openAIModels(Data("{\"error\": {}}".utf8)))
    }

    func testCodexCommandLine() {
        let arguments = CodexExec.arguments(model: "gpt-6-luna", effort: .low, instructions: "/tmp/skilli \"x\"/instructions.md",
                                            directory: "/tmp/skilli-codex")
        XCTAssertEqual(Array(arguments.prefix(2)), ["exec", "--json"])
        for flag in ["--ephemeral", "--skip-git-repo-check", "--ignore-user-config", "--ignore-rules"] {
            XCTAssertTrue(arguments.contains(flag), flag)
        }
        XCTAssertTrue(arguments.joined(separator: " ").contains("-s read-only"))
        XCTAssertTrue(arguments.contains("model_instructions_file=\"/tmp/skilli \\\"x\\\"/instructions.md\""))
        // Every lean feature off, as config (an unknown name is ignored
        // there; `--disable` would stop Codex).
        for feature in ["shell_tool", "unified_exec", "apps", "plugins", "multi_agent"] {
            XCTAssertTrue(arguments.contains("features.\(feature)=false"), feature)
        }
        XCTAssertFalse(arguments.contains("--disable"))
        XCTAssertTrue(arguments.joined(separator: " ").contains("features.realtime_conversation=false -m gpt-6-luna"))
        XCTAssertTrue(arguments.contains("model_reasoning_effort=\"low\""))
        XCTAssertEqual(Array(arguments.suffix(3)), ["-C", "/tmp/skilli-codex", "-"])
        XCTAssertFalse(CodexExec.arguments(model: "gpt-6-luna", effort: nil, instructions: "/i", directory: "/d").contains { $0.hasPrefix("model_reasoning_effort") })
    }

    func testCodexEvents() {
        XCTAssertEqual(CodexExec.event(#"{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"Les enfants ont mangé des pommes."}}"#),
                       .text(id: "item_0", text: "Les enfants ont mangé des pommes."))
        XCTAssertEqual(CodexExec.event(#"{"type":"turn.completed","usage":{"input_tokens":4368}}"#), .completed)
        XCTAssertEqual(CodexExec.event(#"{"type":"error","message":"Reconnecting... 2/5 (unexpected status 401 Unauthorized)"}"#),
                       .retrying("Reconnecting... 2/5 (unexpected status 401 Unauthorized)"))
        XCTAssertEqual(CodexExec.event(#"{"type":"turn.failed","error":{"message":"boom"}}"#), .failed("boom"))
        XCTAssertEqual(CodexExec.event(#"{"type":"item.completed","item":{"id":"item_0","type":"error","message":"Falling back"}}"#), .other)
        XCTAssertEqual(CodexExec.event("not json"), .other)
    }

    func testCodexLogin() {
        XCTAssertEqual(CodexExec.login("Logged in using ChatGPT\n", status: 0), .chatGPT)
        XCTAssertEqual(CodexExec.login("Logged in using an API key - sk-proj-***\n", status: 0), .apiKey)
        XCTAssertEqual(CodexExec.login("Not logged in\n", status: 1), .signedOut)
    }

    func testFailuresInTheUsersWords() {
        let signedOut = "unexpected status 401 Unauthorized: Missing bearer or basic authentication in header, url: https://api.openai.com/v1/responses, cf-ray: a4afb6081fea2c31-CDG"
        XCTAssertTrue(WritingFailure.codex(signedOut).contains("codex login"))
        // A request id that holds "401" is not a sign-out.
        XCTAssertFalse(WritingFailure.codex("stream error, request id: req_401abc").contains("codex login"))
        let model = #"{"type":"error","status":400,"error":{"type":"invalid_request_error","message":"The 'gpt-nope-1' model is not supported when using Codex with a ChatGPT account."}}"#
        XCTAssertEqual(WritingFailure.codex(model), "ChatGPT does not offer “gpt-nope-1” on your plan: pick another model.")
        XCTAssertTrue(WritingFailure.codex("You've hit your usage limit. Try again in 2 hours.").contains("limit is reached"))
        XCTAssertEqual(WritingFailure.message(in: "turn failed: " + model), "The 'gpt-nope-1' model is not supported when using Codex with a ChatGPT account.")

        XCTAssertEqual(WritingFailure.openAI(status: 401, body: #"{"error":{"message":"Incorrect API key provided"}}"#),
                       "OpenAI refused the key: check it in Settings → SI Accounts.")
        XCTAssertTrue(WritingFailure.openAI(status: 429, body: #"{"error":{"code":"insufficient_quota","message":"You exceeded your current quota"}}"#)
            .contains("out of credit"))
        XCTAssertTrue(WritingFailure.openAI(status: 429, body: #"{"error":{"message":"Rate limit reached"}}"#).contains("rate limit"))
        XCTAssertEqual(WritingFailure.openAI(status: 404, body: #"{"error":{"message":"The model `gpt-9` does not exist or you do not have access to it."}}"#),
                       "OpenAI does not offer “gpt-9” to this key: pick another model.")
        XCTAssertTrue(WritingFailure.openAI(status: 503, body: "").contains("try again"))
    }
}
