import SkilliCore
import SwiftUI

/// Rule 2: how the pane's feature is reached, under its header: each
/// Catalog entry's name with its prefix and alias as keycaps, the same as
/// the launcher's "?" shows them. Entries with neither are left out.
struct PaneReach: View {
    /// Catalog entry ids, in the order shown.
    let entries: [String]
    let aliases: [LauncherAlias]

    private var shown: [(title: String, keys: [String])] {
        let all = FeatureCatalog.entries()
        return entries.compactMap { id in
            guard let entry = all.first(where: { $0.id == id }) else { return nil }
            let keys = [entry.prefix?.trimmingCharacters(in: .whitespaces), aliases.first { $0.id == id }?.alias].compactMap { $0 }
                .filter { !$0.isEmpty }
            return keys.isEmpty ? nil : (entry.title, keys)
        }
    }

    var body: some View {
        HStack(spacing: 20) {
            ForEach(shown, id: \.title) { item in
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    ForEach(item.keys, id: \.self) { KeycapLabel($0) }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .textCase(nil)
        .accessibilityElement(children: .combine)
    }
}
