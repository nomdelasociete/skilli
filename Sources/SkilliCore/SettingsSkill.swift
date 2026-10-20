import Foundation

/// The skill that ships with the app: how an agent sets skil.li up with
/// its settings tools (`SettingsTable`). skil.li's MCP server offers it as
/// a resource and a prompt, and its instructions point to it; nothing is
/// written in the agents' own folders.
public enum SettingsSkill {
    public static let name = "set-up-skilli"
    public static let title = "Set up skil.li"
    public static let uri = "skilli://skills/set-up-skilli.md"
    public static let description = "How to change skil.li's settings with its tools: read them first, change one at a time (the user confirms each in skil.li's card), say what changed, never ask for keys."

    /// The skill, in Markdown with the front matter agents' skills use.
    public static let markdown = """
    ---
    name: \(name)
    description: \(description)
    ---

    # Set up skil.li

    skil.li is the user's Mac launcher. Anything its Settings window sets, you can set through skil.li's tools (MCP \
    server "skilli"), under the same name the pane shows, after the user's OK in skil.li's card. The user then sees \
    it in the pane.

    ## Read first
    - Call get_settings before any change (a pane narrows it: get_settings with pane "Backup"). It lists every \
    setting by pane: its name as the pane shows it, its key, its value, its type, the values it takes, and the tools \
    that change it.
    - Use the names and values it gives. Never guess a key or a value.
    - The user's own content (About You, the values in Your Details, people's names, snippets' text, addresses) is \
    only said to be set or not set. Ask the user when you need it; do not look for it elsewhere.

    ## Change one thing at a time
    - set_setting with pane, setting (its name or key) and value. For a list (apps whose copies are never kept, \
    alerts, places, details…): change "add" or "remove", and one item as value.
    - Lists with tools of their own: set_alias and remove_alias (the launcher's aliases); create_quicklink, \
    update_quicklink, delete_quicklink; create_snippet, update_snippet, delete_snippet; add_shortcut, \
    change_shortcut, remove_shortcut (keys such as hyper+y, cmd+shift+k, or a chain hyper+k y; hyper is ✦, the \
    Hyper Key, Caps Lock held).
    - Asks on a schedule (Settings → Ask → On a Schedule): list_scheduled_asks, then add_scheduled_ask (when, as \
    said: “every Monday at 9:00”, “tous les jours à 8h30”; and what to ask then), pause_scheduled_ask, \
    remove_scheduled_ask.
    - One call per change. Each waits for the user's OK in skil.li's card, every time (there is no "always allow" \
    for these), which can take a while: wait for its result. Declined means nothing changed: ask what they want \
    instead.
    - A refusal names the valid values, settings or items: pick one of them, or ask the user.

    ## Say what changed
    - After each call, say in one line what changed, in the pane's words ("Backup: How often → Every week"). Never \
    say something changed unless the tool said so.

    ## Never
    - Never ask for an API key, a token or a password, and never put one in a setting: the user pastes keys in \
    Settings → SI Accounts. get_settings only says whether one is set.
    - Permissions (Accessibility, Calendar, Microphone…) belong to macOS: say where to turn them on (Settings → \
    Privacy), do not try.
    - Tool rights, the approval mode (Approvals), connected servers and the user's own tools are the user's alone: \
    no tool here changes them. Say where they are (Settings → Tools, Settings → Ask).
    - Change only what the user asked for. When a request does not fit a setting exactly, say what the closest one \
    does and ask.

    ## Examples
    - "Add the alias gh for GitHub": set_alias with alias "gh" and item "GitHub". If several items are named \
    GitHub, the refusal lists them with their kind: pass kind too, or ask which.
    - "Back up skil.li every Sunday": get_settings with pane "Backup". Backups go every day, week or month from \
    the last one, with no day of the week: set How often to Every week and say so. If Back up to has no folder yet, \
    ask which folder.
    - "Never keep what I copy from 1Password": set_setting with pane "Clipboard", setting "Never keep copies \
    from", change "add", value "1Password".
    - "Open the launcher with Caps Lock and Y": add_shortcut with action "Open Launcher" and keys "hyper+y".
    """

    /// What skil.li's MCP server says when an agent connects.
    public static let pointer = "To change skil.li's own settings (what its Settings window sets), follow the skill “\(title)” (resource \(uri)): get_settings first, then one change at a time with set_setting or a list's own tools; the user confirms each in skil.li's card, every time. Never ask for API keys or passwords."
}
