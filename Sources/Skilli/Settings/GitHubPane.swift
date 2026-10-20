import SkilliCore
import SwiftUI

/// Settings → GitHub, in the order of the Settings plan's rules: how it is
/// reached ("pr" in the launcher, its alias), the account (GitHub's device
/// flow: a code to type on github.com) and what skil.li read last; the
/// strip under the search field with its preview, drawn by the strip's own
/// view; what leaves the Mac and to whom; then, under Advanced, closed, live
/// updates from the user's own relay.
struct GitHubPane: View {
    @Bindable var preferences: Preferences
    let context: SettingsContext
    /// Shows another pane (Privacy).
    let open: (SettingsPane) -> Void
    @State private var relayURL = ""
    @State private var relayToken = ""
    @State private var relayNote: String?

    private var github: GitHubBook? { context.github }

    var body: some View {
        Form {
            Section {
                ReachRow(title: "From the launcher", detail: "Type pr and a space: your pull requests and notifications.", keys: reach)
                if let github {
                    account(github)
                        .settingAnchor("githubAccount")
                    if github.isSignedIn {
                        lastRead(github)
                    }
                }
            } header: {
                PaneHeader(pane: .github)
            } footer: {
                Text("skil.li reads your pull requests (yours and those waiting for your review) and your notifications with your GitHub account. Merging asks you first.")
            }

            Section {
                Toggle("Show under the search field", isOn: $preferences.githubUnderSearch)
                    .settingAnchor("githubUnderSearch")
                if preferences.githubUnderSearch {
                    GitHubStripPreview()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
            } footer: {
                Text("Your pull requests by group (ready, blocked, waiting, testing) and your unread notifications, right under the search field; a click opens them. While it shows, live updates trigger a new GitHub read. When live updates are unavailable, skil.li checks every minute, or every 15 s while checks run; notifications only when GitHub says something changed.")
            }

            if let line = PrivacyMap.line(for: SettingsPane.github.rawValue, .current(preferences, context)) {
                Section {
                    LeavesMacRow(line: line, open: open)
                }
            }

            if let github, github.isSignedIn {
                RelayEnrollmentControls(session: github.relayDevice, origin: {
                    if preferences.relayPublicURL.isEmpty {
                        preferences.relayPublicURL = "https://relay.nomdelasociete.com"
                        relayURL = preferences.relayPublicURL
                    }
                    return preferences.relayPublicURL
                })
            }

            AdvancedSection(summary: "Server address and legacy token", footer: Self.relayHelp,
                            anchors: ["relayPublicURL", "relayToken"]) {
                TextField("Live updates from", text: $relayURL, prompt: Text(verbatim: "https://updates.example.com"))
                    .onSubmit(saveRelay)
                    .settingAnchor("relayPublicURL")
                if github?.hasRelayToken == true {
                    LabeledContent("Live updates token") {
                        HStack(spacing: 8) {
                            StatusPill(text: "Saved", tint: .green)
                            Button("Remove", role: .destructive) {
                                // At once; ⌘Z in the card saves it again.
                                if let github { context.deletes.relayToken(in: github) }
                                relayNote = nil
                            }
                        }
                    }
                    .settingAnchor("relayToken")
                } else {
                    SecureField("Live updates token", text: $relayToken, prompt: Text("The token your server gave you"))
                        .onSubmit(saveRelay)
                        .settingAnchor("relayToken")
                }
                HStack {
                    if let relayNote {
                        Text(relayNote).font(.callout).foregroundStyle(.red)
                    } else if let problem = github?.relayProblem {
                        Text(problem).font(.callout).foregroundStyle(.orange)
                    } else if relayEnvironment {
                        Text("This session's RELAY_PUBLIC_URL is used instead.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Save", action: saveRelay)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { relayURL = preferences.relayPublicURL }
    }

    /// "pr", then GitHub Inbox's alias when it has one.
    private var reach: [String] {
        let prefix = LauncherPrefix.shown(for: .github)?.trimmingCharacters(in: .whitespaces)
        let alias = preferences.launcherAliases.first { $0.id == "cmd:\(LauncherCommand.ID.github.rawValue)" }?.alias
        return [prefix, alias].compactMap { $0 }
    }

    /// Under Advanced: what the relay is, in its own words.
    static let relayHelp = "Optional server settings. The relay tells skil.li when GitHub changes: while GitHub shows, skil.li holds one "
        + "stream to it instead of reading GitHub every minute. It gets only its own token, never your GitHub sign-in; notifications "
        + "still come from GitHub. Leave the address empty and skil.li reads GitHub on its own."

    private var relayEnvironment: Bool {
        !(ProcessInfo.processInfo.environment["RELAY_PUBLIC_URL"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private func saveRelay() {
        preferences.relayPublicURL = relayURL
        relayURL = preferences.relayPublicURL
        guard !relayToken.isEmpty, let github else {
            relayNote = relayToken.isEmpty ? nil : "Sign in to GitHub first, then save the token."
            return
        }
        do {
            try github.saveRelayToken(relayToken)
            relayToken = ""
            relayNote = nil
        } catch {
            relayNote = error.localizedDescription
        }
    }

    @ViewBuilder
    private func account(_ github: GitHubBook) -> some View {
        if github.isSignedIn {
            LabeledContent("Signed in") {
                HStack {
                    Text(github.login.map { "@\($0)" } ?? "…")
                    Button("Sign Out") { github.signOut() }
                }
            }
        } else if let code = github.signInCode {
            LabeledContent {
                HStack {
                    Text(code.userCode)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)
                    Button("Cancel") { github.cancelSignIn() }
                }
            } label: {
                LabelDetail("Type this code on GitHub", "It is copied, and the page opened in your browser. skil.li signs in by itself once you have typed it there.")
            }
        } else {
            LabeledContent {
                Button("Sign In with GitHub…") { github.signIn() }
                    .disabled(!github.canSignIn)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("GitHub")
                    Text(github.signInProblem ?? (github.canSignIn ? "A code to type on github.com: no password here."
                                                  : "This build of skil.li has no GitHub app to sign in with yet."))
                        .font(.caption).foregroundStyle(github.signInProblem == nil ? Color.secondary : Color.red)
                }
            }
        }
    }

    /// What skil.li read last, when, and Read Now.
    private func lastRead(_ github: GitHubBook) -> some View {
        LabeledContent {
            HStack {
                Text(github.problem ?? github.lastRefresh.map { $0.formatted(date: .omitted, time: .standard) } ?? "Not yet")
                    .foregroundStyle(github.problem == nil ? Color.secondary : Color.orange)
                Button("Read Now") { github.refresh(force: true) }
            }
        } label: {
            LabelDetail("Last read", "\(summary(github)) · \(github.unreadNotifications.count) unread")
        }
    }

    private func summary(_ github: GitHubBook) -> String {
        let text = GitHubInbox.summary(github.pullRequests)
        return text.isEmpty ? "No open pull request" : text
    }
}

private struct RelayEnrollmentControls: View {
    @ObservedObject var session: RelayDeviceSession
    let origin: () -> String
    @State private var confirmRevoke = false

    var body: some View {
        Section {
            if let message = session.message { Text(message).font(.callout).foregroundStyle(.secondary) }
            HStack {
                if !session.canRevoke {
                    Button(session.needsEnrollment ? "Authorize this Mac again…" : "Authorize this Mac…") {
                        session.enroll(origin: origin())
                    }.disabled(session.isBusy)
                } else {
                    Label("\(session.installationCount) GitHub account(s) authorized", systemImage: "checkmark.circle")
                    Button("Manage connected accounts…") { session.enroll(origin: origin()) }
                        .disabled(session.isBusy)
                }
                if session.isEnrolling {
                    Button("Cancel") { session.cancelEnrollment() }
                }
                if session.canRevoke {
                    Button("Revoke this Mac", role: .destructive) { confirmRevoke = true }
                        .disabled(session.isBusy)
                        .confirmationDialog("Revoke live access for this Mac?", isPresented: $confirmRevoke) {
                            Button("Revoke access", role: .destructive) { session.revoke() }
                        } message: {
                            Text("Other computers keep their access. This Mac will use periodic checks until you authorize it again.")
                        }
                }
            }
        } header: {
            Text("Live updates")
        } footer: {
            Text("Select all the GitHub accounts and organizations you want in your browser. Managing accounts replaces the selection only after authorization succeeds. This Mac renews its live access automatically. Your GitHub sign-in token stays on this Mac; GitHub is checked on a timer whenever live updates are unavailable.")
        }
    }
}
