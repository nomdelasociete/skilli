import Foundation

/// Who writes an answer.
public enum WritingProvider: String, CaseIterable, Sendable {
    /// The user's Claude subscription through Claude Code, or a Claude API key.
    case claude
    /// The user's ChatGPT plan, through their own Codex.
    case chatGPT = "chatgpt"
    /// OpenAI's API with the user's key.
    case openAI = "openai"

    public var title: String {
        switch self {
        case .claude: "Claude"
        case .chatGPT: "ChatGPT"
        case .openAI: "OpenAI API"
        }
    }

    /// OpenAI's models think first, for as long as the effort says.
    public var hasEffort: Bool { self != .claude }
}

/// How long an OpenAI model thinks before it writes. Codex also offers
/// xhigh, max and ultra: far too slow for text in a card.
public enum ReasoningEffort: String, CaseIterable, Sendable {
    case low, medium, high

    public var title: String { rawValue.capitalized }
}

/// The model a command writes with: its provider, the model, and for
/// OpenAI's models how long it thinks. In a command file:
///
///     model: haiku                  # Claude, as files always said it
///     model: chatgpt/gpt-6-luna     # ChatGPT through Codex
///     effort: low
///     model: openai/gpt-6.1-sol     # the OpenAI API
///     effort: medium
///
/// Claude's models stay bare, so builds that only knew Claude still read
/// them; `claude/opus` reads too.
public struct ModelChoice: Hashable, Sendable, Identifiable {
    public var provider: WritingProvider
    /// Claude's alias ("haiku") or OpenAI's model id ("gpt-6-luna").
    public var model: String
    /// OpenAI's models only (low when a file says none); nil for Claude.
    public var effort: ReasoningEffort?

    public init(provider: WritingProvider, model: String, effort: ReasoningEffort? = nil) {
        self.provider = provider
        self.model = model
        self.effort = provider.hasEffort ? effort ?? .low : nil
    }

    public static func claude(_ model: String) -> ModelChoice { ModelChoice(provider: .claude, model: model) }

    /// What a command writes with when the user chose nothing.
    public static let standard = ModelChoice.claude("haiku")

    /// Claude's models skil.li runs, fastest first: `claude --model`
    /// aliases.
    public static let claudeModels = ["haiku", "sonnet", "opus"]

    /// What a file's `model:` and `effort:` say.
    public enum Parsed: Equatable, Sendable {
        /// Nothing, or "default": Settings → SI Accounts' default.
        case standard
        case choice(ModelChoice)
        /// A provider or model this build cannot run (a newer file, a typo):
        /// the command writes with the default and says so.
        case unknown(String)
    }

    public static func parse(model: String?, effort: String? = nil) -> Parsed {
        let text = (model ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty, text != "default" else { return .standard }
        let parts = text.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let provider = parts.count == 2 ? WritingProvider(rawValue: parts[0]) : .claude
        let name = parts.count == 2 ? parts[1] : text
        guard let provider else { return .unknown(text) }
        switch provider {
        case .claude:
            return claudeModels.contains(name) ? .choice(.claude(name)) : .unknown(text)
        case .chatGPT, .openAI:
            guard isModelID(name) else { return .unknown(text) }
            let level = effort.flatMap { ReasoningEffort(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased()) }
            return .choice(ModelChoice(provider: provider, model: name, effort: level))
        }
    }

    /// OpenAI's model ids: lowercase letters, digits, dots, dashes and
    /// underscores, 64 at most. Anything else (a space, a leading dash a
    /// command line would read as an option) is refused: shared commands
    /// come from links.
    public static func isModelID(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        guard let first = scalars.first, scalars.count <= 64, ("a"..."z").contains(first) || ("0"..."9").contains(first) else { return false }
        return scalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || ".-_".unicodeScalars.contains($0) }
    }

    /// `model:` as a file says it: bare for Claude.
    public var fileModel: String {
        provider == .claude ? model : "\(provider.rawValue)/\(model)"
    }

    /// `effort:` as a file says it.
    public var fileEffort: String? { effort?.rawValue }

    /// One string for preferences: "claude/haiku", "chatgpt/gpt-6-luna@low".
    public var id: String {
        "\(provider.rawValue)/\(model)" + (effort.map { "@\($0.rawValue)" } ?? "")
    }

    public init?(id: String) {
        let parts = id.split(separator: "@", maxSplits: 1).map(String.init)
        guard case .choice(let choice) = Self.parse(model: parts.first, effort: parts.count == 2 ? parts[1] : nil) else { return nil }
        self = choice
    }

    /// The model alone: "Haiku", "GPT-6 Luna".
    public var modelTitle: String {
        provider == .claude ? model.capitalized : Self.modelTitle(model)
    }

    /// With its effort, as Raycast says it: "Haiku", "GPT-6 Luna Low".
    public var title: String {
        effort.map { "\(modelTitle) \($0.title)" } ?? modelTitle
    }

    /// "ChatGPT · GPT-6 Luna Low".
    public var label: String { "\(provider.title) · \(title)" }

    /// The same model at another effort (Claude's stay as they are).
    public func with(effort: ReasoningEffort) -> ModelChoice {
        ModelChoice(provider: provider, model: model, effort: effort)
    }

    /// "gpt-6-luna" → "GPT-6 Luna", "gpt-6.1-sol" → "GPT-6.1 Sol".
    public static func modelTitle(_ id: String) -> String {
        var words = id.split(separator: "-").map(String.init)
        guard !words.isEmpty else { return id }
        var head = words.removeFirst()
        if head == "gpt" {
            head = "GPT"
            if let version = words.first, version.first?.isNumber == true {
                head += "-" + version
                words.removeFirst()
            }
        } else {
            head = head.prefix(1).uppercased() + head.dropFirst()
        }
        return ([head] + words.map { $0.prefix(1).uppercased() + $0.dropFirst() }).joined(separator: " ")
    }
}

/// A model a provider offers, and the efforts it takes (empty: none).
public struct ModelOffer: Hashable, Sendable, Identifiable {
    public let id: String
    public let efforts: [ReasoningEffort]

    public init(id: String, efforts: [ReasoningEffort]) {
        self.id = id
        self.efforts = efforts
    }
}

/// The OpenAI models offered for writing, from what Codex and the API list.
public enum ModelCatalog {
    /// Checked with real requests through Codex on 2026-10-15 (codex-cli
    /// 0.162.1, a ChatGPT plan; `supported_in_api` in its catalog): what is
    /// offered before Codex or the API were asked.
    public static let verified = [
        ModelOffer(id: "gpt-6.1-sol", efforts: ReasoningEffort.allCases),
        ModelOffer(id: "gpt-6-astra", efforts: ReasoningEffort.allCases),
        ModelOffer(id: "gpt-6-luna", efforts: ReasoningEffort.allCases)
    ]

    /// Claude's models, which take no effort here.
    public static let claude = ModelChoice.claudeModels.map { ModelOffer(id: $0, efforts: []) }

    /// `codex debug models`: the models it lists (not the hidden ones), in
    /// its order, with the efforts it takes among low, medium and high.
    /// nil when the output is not that catalog.
    public static func codexModels(_ data: Data) -> [ModelOffer]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]]
        else { return nil }
        var offers: [ModelOffer] = []
        for model in models {
            guard let id = model["slug"] as? String, ModelChoice.isModelID(id),
                  (model["visibility"] as? String ?? "list") == "list",
                  !offers.contains(where: { $0.id == id })
            else { continue }
            let levels = (model["supported_reasoning_levels"] as? [[String: Any]] ?? []).compactMap { $0["effort"] as? String }
            let efforts = ReasoningEffort.allCases.filter { levels.contains($0.rawValue) }
            offers.append(ModelOffer(id: id, efforts: efforts.isEmpty ? [.low] : efforts))
        }
        return offers
    }

    /// `GET /v1/models`: the GPT models that write text (no audio, images,
    /// speech, search, embeddings, moderation, code, dated snapshots), newest
    /// first. nil when the body is not a model list.
    public static func openAIModels(_ data: Data) -> [ModelOffer]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]]
        else { return nil }
        let excluded = ["audio", "realtime", "tts", "transcribe", "image", "search", "embedding", "moderation", "instruct",
                        "codex", "research", "computer", "chat", "preview", "oss", "reserve", "review"]
        var names: [GPTName] = []
        for id in Set(models.compactMap { $0["id"] as? String }) {
            guard ModelChoice.isModelID(id), let name = GPTName(id),
                  !name.family.contains(where: { word in excluded.contains { word.hasPrefix($0) } }),
                  // Dated snapshots: "gpt-6-luna-2026-09-01".
                  !name.family.contains(where: { $0.count >= 4 && $0.allSatisfy(\.isNumber) })
            else { continue }
            names.append(name)
        }
        // Newest first; one version: by name.
        return names
            .sorted { $0.version != $1.version ? $1.version.lexicographicallyPrecedes($0.version) : $0.id < $1.id }
            .map { ModelOffer(id: $0.id, efforts: ReasoningEffort.allCases) }
    }

    /// What the menus show: the newest model of each family, and only the
    /// families of the newest generation: GPT-6.1 Sol, GPT-6 Astra and GPT-6
    /// Luna, not GPT-6 Sol or GPT-5.6 Terra. Ids that are not
    /// "gpt-<version>-…" stay. Order kept.
    public static func current(_ offers: [ModelOffer]) -> [ModelOffer] {
        let names = offers.compactMap { GPTName($0.id) }
        guard let generation = names.map({ $0.version[0] }).max() else { return offers }
        return offers.filter { offer in
            guard let name = GPTName(offer.id) else { return true }
            return name.version[0] == generation
                && !names.contains { $0.family == name.family && name.version.lexicographicallyPrecedes($0.version) }
        }
    }

    /// "gpt-6.1-sol" → version [6, 1], family ["sol"].
    struct GPTName {
        let id: String
        let version: [Int]
        let family: [String]

        init?(_ id: String) {
            let words = id.split(separator: "-").map(String.init)
            guard words.count >= 2, words[0] == "gpt" else { return nil }
            let numbers = words[1].split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
            guard !numbers.isEmpty, numbers.allSatisfy({ $0 != nil }) else { return nil }
            self.id = id
            version = numbers.compactMap { $0 }
            family = Array(words.dropFirst(2))
        }
    }
}
