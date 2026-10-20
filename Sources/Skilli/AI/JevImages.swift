import AppKit
import Foundation

/// Jev judging images (TypeSafe's "Images", Dreamer-ready: each request
/// says `TypeSafe-Danger-Zone-Images: true`). An image is a reference in
/// the state or in an option's criteria, its bytes in `assets`. Billed as
/// input tokens like text; `usage` says how many.
enum JevImages {
    struct Image: Sendable {
        /// The reference used in the state or the criteria: unique, never
        /// a word that could appear elsewhere.
        let reference: String
        let data: Data
        /// "jpeg" or "png".
        let format: String
    }

    enum Question: Sendable {
        /// One option among several, described in words or by an image
        /// reference.
        case choice(name: String, instructions: String, options: [(value: String, criteria: String)])
        /// A yes or no: the answer's probability of yes.
        case noul(name: String, instructions: String)
    }

    struct Answers: Sendable {
        let results: [String: DecisionResult]
        let inputTokens: Int
        let model: String
        let milliseconds: Double
    }

    static func judge(state: [String: any Sendable], images: [Image], questions: [Question], key: String,
                      model: String = "jev-latest") async throws -> Answers {
        var request = URLRequest(url: URL(string: "https://api.typesafe.ai/v1/systemone")!)
        let body: [String: Any] = [
            "model": model,
            "state": state,
            "assets": Dictionary(uniqueKeysWithValues: images.map { image in
                (image.reference, ["type": "image", "format": image.format, "data_base64": image.data.base64EncodedString()] as [String: Any])
            }),
            "questions": Dictionary(uniqueKeysWithValues: questions.map { question -> (String, [String: Any]) in
                switch question {
                case let .choice(name, instructions, options):
                    (name, ["type": "choice", "instructions": instructions,
                            "criteria": Dictionary(options.map { ($0.value, $0.criteria) }, uniquingKeysWith: { first, _ in first })])
                case let .noul(name, instructions):
                    (name, ["type": "noul", "instructions": instructions])
                }
            })
        ]
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "TypeSafe-Danger-Zone-Images")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let start = ContinuousClock.now
        let (data, response) = try await URLSession.shared.data(for: request)
        let elapsed = ContinuousClock.now - start
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard status == 200, let json else {
            let message = (json?["error"] as? [String: Any])?["message"] as? String ?? json?["detail"] as? String
                ?? String(decoding: data.prefix(300), as: UTF8.self)
            throw AIError.failed("TypeSafe Jev (images): \(message) (\(status))")
        }
        var results: [String: DecisionResult] = [:]
        let answers = json["answers"] as? [String: Any] ?? [:]
        for question in questions {
            switch question {
            case let .choice(name, _, _):
                guard let answer = answers[name] as? [String: Any], let choice = answer["choice"] as? String else { continue }
                results[name] = DecisionResult(choice: choice, confidence: answer["confidence"] as? Double ?? 0,
                                               probabilities: answer["probabilities"] as? [String: Double] ?? [:])
            case let .noul(name, _):
                guard let answer = answers[name] as? [String: Any], let yes = answer["noul"] as? Double else { continue }
                results[name] = DecisionResult(choice: yes >= 0.5 ? "yes" : "no", confidence: yes, probabilities: ["yes": yes, "no": 1 - yes])
            }
        }
        let usage = json["usage"] as? [String: Any]
        return Answers(results: results, inputTokens: usage?["input_tokens"] as? Int ?? 0, model: json["model"] as? String ?? model,
                       milliseconds: Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15)
    }

    /// Where something is in a picture: TypeSafe's Box (Jev 1.14), its
    /// edges as fractions of the picture (top-left origin), how sure; and
    /// whether it is there at all, a Noul asked beside it (a Box always
    /// answers a box).
    struct Located: Sendable {
        let box: CGRect
        let confidence: Double
        let present: Double
        let inputTokens: Int
        let milliseconds: Double
    }

    /// Box questions need Jev 1.14.
    static let boxModel = "jev-1.14.0"

    static func locate(state: [String: any Sendable], images: [Image], target: String, presence: String, key: String) async throws -> Located {
        var request = URLRequest(url: URL(string: "https://api.typesafe.ai/v1/systemone")!)
        let body: [String: Any] = [
            "model": boxModel,
            "state": state,
            "assets": Dictionary(uniqueKeysWithValues: images.map { image in
                (image.reference, ["type": "image", "format": image.format, "data_base64": image.data.base64EncodedString()] as [String: Any])
            }),
            "questions": [
                "where": ["type": "box", "instructions": target],
                "present": ["type": "noul", "instructions": presence]
            ]
        ]
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "TypeSafe-Danger-Zone-Images")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let start = ContinuousClock.now
        let (data, response) = try await URLSession.shared.data(for: request)
        let elapsed = ContinuousClock.now - start
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard status == 200, let json else {
            let message = (json?["error"] as? [String: Any])?["message"] as? String ?? json?["detail"] as? String
                ?? String(decoding: data.prefix(300), as: UTF8.self)
            throw AIError.failed("TypeSafe Jev (box): \(message) (\(status))")
        }
        let answers = json["answers"] as? [String: Any] ?? [:]
        guard let answer = answers["where"] as? [String: Any], let edges = answer["box"] as? [String: Any],
              let left = edges["left"] as? Double, let right = edges["right"] as? Double,
              let top = edges["top"] as? Double, let bottom = edges["bottom"] as? Double else {
            throw AIError.failed("TypeSafe Jev (box): no box")
        }
        // No Noul back (declined): unknown, not sure either way.
        let present = (answers["present"] as? [String: Any])?["noul"] as? Double ?? 0.5
        let usage = json["usage"] as? [String: Any]
        return Located(box: CGRect(x: left, y: top, width: max(0, right - left), height: max(0, bottom - top)),
                       confidence: answer["confidence"] as? Double ?? 0, present: present,
                       inputTokens: usage?["input_tokens"] as? Int ?? 0,
                       milliseconds: Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15)
    }

    /// `image` as JPEG with its longest side `longest` (TypeSafe takes 256
    /// to 1568 px a side): smaller sides padded up to 256 on white.
    static func jpeg(_ image: NSImage, longest: CGFloat, quality: CGFloat = 0.82) -> Data? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = CGFloat(source.width), height = CGFloat(source.height)
        let scale = min(1, longest / max(width, height))
        let drawn = CGSize(width: (width * scale).rounded(), height: (height * scale).rounded())
        // At least 280 a side: TypeSafe wants 78,400 pixels or more.
        let canvas = CGSize(width: max(280, drawn.width), height: max(280, drawn.height))
        guard let context = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: canvas))
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: (canvas.width - drawn.width) / 2, y: (canvas.height - drawn.height) / 2,
                                        width: drawn.width, height: drawn.height))
        guard let resized = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: resized).representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}
