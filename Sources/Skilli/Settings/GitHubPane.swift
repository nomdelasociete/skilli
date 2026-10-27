import SkilliCore
import SwiftUI

/// Settings → GitHub, in the order of the Settings plan's rules: how it is
/// reached ("pr" in the launcher, its alias), the account (one browser tab:
/// the relay's live updates and server sync, then GitHub's device code,
/// docs/github-single-sign-in.md) and what skil.li read last; the
/// strip under the search field with its preview, drawn by the strip's own
/// view; what leaves the Mac and to whom; live updates (this Mac's relay
/// access), then server sync (the relay reads GitHub for the user's Macs);
/// then, under Advanced, closed, the relay's address and legacy token.
struct GitHubPane: View {
    @Bindable var preferences: Preferences
    let context: SettingsContext
    /// Shows another pane (Privacy).
    let open: (SettingsPane) -> Void
    @State private var relayURL = ""
    @State private var relayToken = ""
    @State private var relayNote: String?
    /// Server sync's checkbox beside the sign-in, the consent given before
    /// the browser trip.
    @State private var serverSyncWanted = true

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
                Text(preferences.githubServerSync
                     ? "The relay reads your pull requests (yours and those waiting for your review) and your notifications for your Macs (Server sync, below); skil.li acts with your GitHub account. Merging asks you first."
                     : "skil.li reads your pull requests (yours and those waiting for your review) and your notifications with your GitHub account. Merging asks you first.")
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
                RelayEnrollmentControls(session: github.relayDevice, origin: relayOrigin,
                                        serverSync: preferences.githubServerSync ? nil : $serverSyncWanted,
                                        serverSyncReady: { github.confirmServerSyncGrant { turnOnServerSync() } })
                if github.relayDevice.canRevoke || preferences.githubServerSync {
                    ServerSyncControls(preferences: preferences, github: github)
                }
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
        .onAppear {
            relayURL = preferences.relayPublicURL
            github?.showsSettings = true
        }
        .onDisappear { github?.showsSettings = false }
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

    /// The relay's address GitHubBook connects to: this session's
    /// RELAY_PUBLIC_URL when set, else the setting, the default one written
    /// the first time. The pairing is bound to it.
    private func relayOrigin() -> String {
        let environment = (ProcessInfo.processInfo.environment["RELAY_PUBLIC_URL"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !environment.isEmpty { return environment }
        if preferences.relayPublicURL.isEmpty {
            preferences.relayPublicURL = "https://relay.nomdelasociete.com"
            relayURL = preferences.relayPublicURL
        }
        return preferences.relayPublicURL
    }

    /// The relay holds the grant now: on, unless the box was unticked
    /// while the browser trip went on.
    private func turnOnServerSync() {
        if serverSyncWanted { preferences.githubServerSync = true }
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
                    // GitHub's page at once, without waiting for the relay's tab.
                    Button("Open GitHub") { github.open(code.verificationURL) }
                    Button("Cancel") { github.cancelSignIn() }
                }
            } label: {
                LabelDetail("Finish in your browser", "The code is copied; GitHub asks for it last. skil.li signs in by itself once you have typed it there.")
            }
        } else {
            LabeledContent {
                Button("Sign In with GitHub…") {
                    github.signIn(relayOrigin: relayOrigin(), serverSync: serverSyncWanted,
                                  serverSyncReady: { turnOnServerSync() })
                }
                .disabled(!github.canSignIn)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("GitHub")
                    Text(github.signInProblem ?? (github.canSignIn ? "One trip in your browser: live updates, then a code to type on github.com. No password here."
                                                  : "This build of skil.li has no GitHub app to sign in with yet."))
                        .font(.caption).foregroundStyle(github.signInProblem == nil ? Color.secondary : Color.red)
                }
            }
            if github.canSignIn {
                ServerSyncChoice(wanted: $serverSyncWanted)
            }
        }
    }

    /// What skil.li read last, when, and Read Now.
    private func lastRead(_ github: GitHubBook) -> some View {
        LabeledContent {
            HStack {
                Text(github.problem ?? github.lastRefresh.map { $0.formatted(date: .omitted, time: .standard) } ?? "Not yet")
                    .foregroundStyle(github.problem == nil ? Color.secondary : Color.orange)
                Button("Read Now") { github.readNow() }
            }
        } label: {
            LabelDetail("Last read", "\(summary(github)) · \(github.unreadNotifications.count)\(github.notificationsComplete ? "" : "+") unread")
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
    /// Server sync in the same trip, while it is off on this Mac.
    let serverSync: Binding<Bool>?
    /// The grant was asked for in the tab: confirms it, then turns server sync on.
    let serverSyncReady: () -> Void
    @State private var confirmRevoke = false

    private func enroll() {
        // The checkbox shows only before this Mac is paired: managing
        // accounts asks for nothing more.
        session.enroll(origin: origin(), chain: RelaySignInChain(inbox: !session.canRevoke && serverSync?.wrappedValue == true),
                       paired: { if $0 { serverSyncReady() } })
    }

    var body: some View {
        Section {
            if let message = session.message { Text(message).font(.callout).foregroundStyle(.secondary) }
            HStack {
                if !session.canRevoke {
                    Button(session.needsEnrollment ? "Authorize this Mac again…" : "Authorize this Mac…") {
                        enroll()
                    }.disabled(session.isBusy)
                } else {
                    Label("\(session.installationCount) GitHub account(s) authorized", systemImage: "checkmark.circle")
                    Button("Manage connected accounts…") { enroll() }
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
            if !session.canRevoke, let serverSync {
                ServerSyncChoice(wanted: serverSync)
            }
        } header: {
            Text("Live updates")
        } footer: {
            Text("Select all the GitHub accounts and organizations you want in your browser. Managing accounts replaces the selection only after authorization succeeds. This Mac renews its live access automatically. Your GitHub sign-in token stays on this Mac; GitHub is checked on a timer whenever live updates are unavailable.")
        }
    }
}

/// Server sync chosen before the browser trip (sign-in, live updates): the
/// consent in full under the checkbox, so the trip needs no alert.
private struct ServerSyncChoice: View {
    @Binding var wanted: Bool

    var body: some View {
        Toggle(isOn: $wanted) {
            LabelDetail("Keep my pull requests on the relay for all my Macs (server sync)", ServerSyncControls.consent)
        }
        .toggleStyle(.checkbox)
    }
}

/// Server sync: the relay reads pull requests and notifications on GitHub
/// with its own authorization, one copy for all the user's Macs. Turning it
/// on says first what it reads and keeps; turning it off here is this Mac
/// only; deleting is for every Mac.
private struct ServerSyncControls: View {
    @Bindable var preferences: Preferences
    let github: GitHubBook
    @State private var confirmOn = false
    @State private var confirmDelete = false
    @State private var working = false
    @State private var note: String?

    static let consent = "The relay reads your pull requests (yours and those waiting for your review) and your unread notifications "
        + "on GitHub, with an authorization you give on GitHub in your browser (scopes repo, notifications and read:user; repo also allows changes, "
        + "the relay only reads). It keeps one encrypted copy for your Macs authorized for live updates: titles, links, repositories, "
        + "review states, checks, your permissions, notification titles and reasons; never code, descriptions or comments. The copy "
        + "goes after 24 hours unused, the authorization after 90 days. Merging, updating a branch and marking read stay on this Mac, "
        + "with your own sign-in. This Mac then reads GitHub only through the relay."

    var body: some View {
        Section {
            if preferences.githubServerSync {
                LabeledContent {
                    Text(status).foregroundStyle(github.serverHold == nil ? Color.secondary : Color.orange)
                } label: {
                    LabelDetail("Read through the relay", "This Mac does not read GitHub itself while this is on.")
                }
                .settingAnchor("githubServerSync")
                HStack {
                    if github.serverHold == .authorizationRequired {
                        Button("Authorize in Browser…") { run { try await github.authorizeServerSync() } }
                            .disabled(working || !github.canAuthorizeServerSync)
                    }
                    Spacer()
                    Button("Turn Off on This Mac") { preferences.githubServerSync = false; note = nil }
                    Button("Delete for All Macs…", role: .destructive) { confirmDelete = true }
                        .disabled(working || !github.canAuthorizeServerSync)
                }
            } else {
                LabeledContent {
                    Button("Turn On…") { confirmOn = true }
                        .disabled(working || !github.canAuthorizeServerSync)
                } label: {
                    LabelDetail("Read through the relay", github.canAuthorizeServerSync
                        ? "One read of GitHub for all your Macs, instead of one per Mac."
                        : "First authorize this Mac for live updates, signed in to the same GitHub account.")
                }
                .settingAnchor("githubServerSync")
            }
            if let note { Text(note).font(.callout).foregroundStyle(.red) }
        } header: {
            Text("Server sync")
        } footer: {
            Text("Live updates only say when something changed; server sync also reads for you. Turn Off on This Mac goes back to reading "
                 + "GitHub from this Mac; Delete for All Macs removes the relay's authorization and copy for all of them. GitHub keeps "
                 + "listing the authorization under Settings → Applications until you revoke it there.")
        }
        .alert("Read GitHub through the relay?", isPresented: $confirmOn) {
            Button("Continue") {
                preferences.githubServerSync = true
                run { try await github.startServerSync() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Self.consent)
        }
        .confirmationDialog("Delete server sync for all your Macs?", isPresented: $confirmDelete) {
            Button("Delete for All Macs", role: .destructive) {
                run {
                    try await github.deleteServerSync()
                    preferences.githubServerSync = false
                }
            }
        } message: {
            Text("The relay forgets its authorization and its copy. Each Mac that uses server sync then needs a new authorization.")
        }
    }

    private var status: String {
        if let hold = github.serverHold { return hold.message }
        guard let read = github.lastRefresh else { return "Reading…" }
        return "Read \(read.formatted(date: .omitted, time: .standard))"
    }

    private func run(_ work: @escaping () async throws -> Void) {
        working = true
        note = nil
        Task {
            do { try await work() } catch { note = error.localizedDescription }
            working = false
        }
    }
}
