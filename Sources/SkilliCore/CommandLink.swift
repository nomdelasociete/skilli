import Foundation

/// Links that install commands: `skilli://commands/import?command=<file>`
/// (the whole Markdown file, repeatable) or `?url=https://…/command.md`.
/// The full file travels, so output, questions and model are kept.
public enum CommandLink {
    public static let scheme = "skilli"

    public struct Request: Equatable, Sendable {
        /// Command files carried in the link.
        public var files: [String]
        /// Command files to download (https only).
        public var urls: [URL]

        public init(files: [String] = [], urls: [URL] = []) {
            self.files = files
            self.urls = urls
        }
    }

    /// nil for anything that is not an import link with at least one command.
    public static func parse(_ url: URL) -> Request? {
        guard url.scheme?.lowercased() == scheme, url.host()?.lowercased() == "commands",
              url.path() == "/import" || url.path() == "/import/",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        var request = Request()
        for item in items {
            guard let value = item.value, !value.isEmpty else { continue }
            switch item.name {
            case "command": request.files.append(value)
            case "url":
                if let remote = URL(string: value), remote.scheme?.lowercased() == "https", remote.host() != nil {
                    request.urls.append(remote)
                }
            default: break
            }
        }
        return request.files.isEmpty && request.urls.isEmpty ? nil : request
    }

    /// A link carrying `files`, for Copy Link.
    public static func importLink(for files: [String]) -> URL {
        // `+` and `&` encoded too: web pages read `+` as a space.
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=#?/")
        let query = files
            .map { "command=" + ($0.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") }
            .joined(separator: "&")
        return URL(string: "\(scheme)://commands/import?\(query)")!
    }
}
