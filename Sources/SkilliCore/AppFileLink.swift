import Foundation

/// Links that add linked apps (docs/apps.md, "App files"):
/// `skilli://apps/import?app=<the file>` (the whole JSON, repeatable) or
/// `?url=https://…/app.json`. Settings → Apps shows every app whole before
/// Add, as `CommandLink` does for commands; nothing is added from a link
/// alone.
public enum AppFileLink {
    public struct Request: Equatable, Sendable {
        /// App files carried in the link.
        public var files: [String]
        /// App files to download (https only).
        public var urls: [URL]

        public init(files: [String] = [], urls: [URL] = []) {
            self.files = files
            self.urls = urls
        }
    }

    /// nil for anything that is not an import link with at least one app.
    public static func parse(_ url: URL) -> Request? {
        guard url.scheme?.lowercased() == CommandLink.scheme, url.host()?.lowercased() == "apps",
              url.path() == "/import" || url.path() == "/import/",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        var request = Request()
        for item in items {
            guard let value = item.value, !value.isEmpty else { continue }
            switch item.name {
            case "app": request.files.append(value)
            case "url":
                if let remote = URL(string: value), remote.scheme?.lowercased() == "https", remote.host() != nil {
                    request.urls.append(remote)
                }
            default: break
            }
        }
        return request.files.isEmpty && request.urls.isEmpty ? nil : request
    }

    /// A link carrying `files`, to share an app.
    public static func importLink(for files: [String]) -> URL {
        // `+` and `&` encoded too: web pages read `+` as a space.
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=#?/")
        let query = files
            .map { "app=" + ($0.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") }
            .joined(separator: "&")
        return URL(string: "\(CommandLink.scheme)://apps/import?\(query)")!
    }
}
