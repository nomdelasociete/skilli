import SkilliCore
import SwiftUI

/// Who writes: one menu grouped by provider (Claude, ChatGPT, OpenAI API),
/// then, for OpenAI's models, how long they think. A provider that cannot
/// write now stays listed, its models off and its header saying why and
/// how. Used by the command editor and Settings → SI Accounts.
struct ModelPicker: View {
    let ai: AIStore
    @Binding var choice: ModelChoice?
    /// The editor's first entry, which follows Settings → SI Accounts ("Default
    /// (Claude · Haiku)"); nil for Settings → SI Accounts' own default.
    var defaultTitle: String?
    /// Commands with tools run in Claude Code: Claude's models only.
    var claudeOnly = false
    /// A provider that cannot write says how to fix it ("No key: add one
    /// in Settings → SI Accounts"); in SI Accounts itself only why ("No
    /// key"): the rows under the menu fix it.
    var saysHow = true

    var body: some View {
        // A pop-up like every other choice in Settings; its title names the
        // provider too ("ChatGPT · GPT-6 Luna"), its menu only the models.
        Picker("Model", selection: Binding(get: { choice.map(Self.key) }, set: select)) {
            if let defaultTitle {
                Text(defaultTitle).tag(String?.none)
                Divider()
            }
            ForEach(providers, id: \.self) { provider in
                Section(header(provider)) {
                    ForEach(entries(provider)) { offer in
                        Text(ModelChoice(provider: provider, model: offer.id).modelTitle)
                            .tag(Optional("\(provider.rawValue)/\(offer.id)"))
                            .selectionDisabled(!isReady(provider))
                    }
                }
            }
        } currentValueLabel: {
            Text(title)
        }
        if let current = choice, current.provider.hasEffort {
            // Its own row, the control on the right like every value: a
            // segmented picker alone sits in the middle of a grouped form.
            LabeledContent("Thinking") {
                Picker("Thinking", selection: Binding(
                    get: { current.effort ?? .low },
                    set: { choice = current.with(effort: $0) }
                )) {
                    ForEach(efforts(for: current), id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
            .help("How long the model thinks before it writes. Low answers fastest.")
        }
    }

    /// One menu item per model, whatever its effort.
    private static func key(_ choice: ModelChoice) -> String { "\(choice.provider.rawValue)/\(choice.model)" }

    private func select(_ key: String?) {
        guard let key else {
            choice = nil
            return
        }
        guard case .choice(let picked) = ModelChoice.parse(model: key) else { return }
        let offer = entries(picked.provider).first { $0.id == picked.model }
        // Another model keeps the effort already chosen, when it takes it.
        let effort = choice?.effort.flatMap { offer?.efforts.contains($0) == true ? $0 : nil } ?? offer?.efforts.first
        choice = ModelChoice(provider: picked.provider, model: picked.model, effort: effort)
    }

    private var providers: [WritingProvider] {
        claudeOnly ? [.claude] : WritingProvider.allCases
    }

    /// "ChatGPT · GPT-6 Luna": the effort has its own row.
    private var title: String {
        guard let choice else { return defaultTitle ?? "Default" }
        return "\(choice.provider.title) · \(choice.modelTitle)"
    }

    private func header(_ provider: WritingProvider) -> String {
        guard case .unavailable(let why, let how) = ai.availability(provider) else { return provider.title }
        return "\(provider.title) — \(saysHow ? "\(why): \(how)" : why)"
    }

    private func isReady(_ provider: WritingProvider) -> Bool {
        switch ai.availability(provider) {
        case .ready, .checking: true
        case .unavailable: false
        }
    }

    /// The provider's models, and the current one when the lists do not
    /// have it (an older model named in a file).
    private func entries(_ provider: WritingProvider) -> [ModelOffer] {
        var offers = ai.models(provider)
        if let choice, choice.provider == provider, !offers.contains(where: { $0.id == choice.model }) {
            offers.append(ModelOffer(id: choice.model, efforts: provider.hasEffort ? ReasoningEffort.allCases : []))
        }
        return offers
    }

    private func efforts(for choice: ModelChoice) -> [ReasoningEffort] {
        let offered = ai.models(choice.provider).first { $0.id == choice.model }?.efforts ?? ReasoningEffort.allCases
        return offered.isEmpty ? ReasoningEffort.allCases : offered
    }
}
