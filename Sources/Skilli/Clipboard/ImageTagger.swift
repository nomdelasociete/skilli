import AppKit
import SkilliCore

/// What an image shows, by Jev (`ImageTags`): a 512 px copy is sent once,
/// in one request: its kind, and whether there is a person in it. About
/// 1,000 input tokens: $0.00004 at TypeSafe's price.
enum ImageTagger {
    static func tags(for url: URL, key: String) async -> ImageTags? {
        guard let image = NSImage(contentsOf: url), let data = JevImages.jpeg(image, longest: 512) else { return nil }
        let reference = "image-\(UUID().uuidString)"
        do {
            let answers = try await JevImages.judge(
                state: [ImageTags.imageField: reference], images: [.init(reference: reference, data: data, format: "jpeg")],
                questions: [
                    .choice(name: ImageTags.kindQuestion, instructions: ImageTags.kindInstructions,
                            options: ImageTags.Kind.allCases.map { ($0.rawValue, $0.criteria) }),
                    .noul(name: ImageTags.personQuestion, instructions: ImageTags.personInstructions)
                ],
                key: key)
            let kind = answers.results[ImageTags.kindQuestion]
            return ImageTags(kind: kind?.choice, kindProbability: kind.map { $0.probabilities[$0.choice] ?? 0 } ?? 0,
                             personProbability: answers.results[ImageTags.personQuestion]?.confidence)
        } catch {
            Log.actions.error("Image tags: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
