import AppKit
import SkilliCore
import SwiftUI

/// A contact in the card as Apple's Contacts shows one: the photo (or the
/// monogram on Contacts' gray), the name, what they do and where; then
/// each field, its label on the left. What can be done is in ⌘K, the same
/// list as the launcher's.
struct ContactCardView: View {
    let record: ContactRecord
    let photo: NSImage?
    /// Rows at most, to fit the card; the rest: "N more in Contacts".
    let maxRows: Int

    private var work: String {
        let parts = [record.jobTitle, record.department, record.organization].filter { !$0.isEmpty }
        return record.name == record.organization ? "" : parts.joined(separator: " · ")
    }

    var body: some View {
        let rows = record.cardRows
        let shown = Array(rows.prefix(maxRows))
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                avatar
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.name)
                        .font(.system(size: 18, weight: .semibold))
                        .lineLimit(1)
                    if !work.isEmpty {
                        Text(work)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if !record.nickname.isEmpty {
                        Text("“\(record.nickname)”")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            if !shown.isEmpty {
                Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 8) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            Text(row.label)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(width: 72, alignment: .trailing)
                            Text(row.value)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                                .lineLimit(row.label == "note" ? 3 : 4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if rows.count > shown.count {
                Text("\(rows.count - shown.count) more in Contacts")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 84)
            }
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Contact \(record.name)")
    }

    @ViewBuilder
    private var avatar: some View {
        if let photo {
            Image(nsImage: photo)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            // Contacts' monogram: white letters on its soft gray.
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.69), Color(white: 0.55)], startPoint: .top, endPoint: .bottom))
                .overlay(
                    Text(record.initials)
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                )
        }
    }
}
