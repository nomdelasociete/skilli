# Calling skil.li from a skillie

A skillie reaches skil.li's features in two ways:

| | `open "skilli://…"` | `"$SKILLI_CLI" call <tool> …` |
| --- | --- | --- |
| Waits | No: fire and forget | Yes: until the tool answers |
| Result | None | Text on standard output, exit status |
| Asked first | By the link rules (what could change the Mac asks) | By your approval mode and the tool's right |
| Works outside skil.li | Yes, from anything that opens a URL | Yes, as `Skilli call` from Terminal ([below](#outside-a-skillie)); `$SKILLI_CLI` itself is set only in a skillie skil.li runs, and `--socket` picks another skil.li |

Recipes for each feature (CleanShot, windows, Keep Awake, the recorder,
Shortcuts…) are in the collection's guide:
[Use skil.li's other features](../README.md#use-skillis-other-features).
This page is the reference.

## `"$SKILLI_CLI" call`

```bash
"$SKILLI_CLI" call <tool> [name=value …]
"$SKILLI_CLI" call <tool> '{"name": "value", "list": ["a", "b"]}'
```

- `SKILLI_CLI` is the skil.li binary that runs the skillie
  ([running.md](running.md#environment)). Always quote it: the path has a
  space in it on some Macs.
- Arguments are `name=value` words, each value a string. Quote each word
  (`goal="$1"`) so a value with spaces stays one value. A name is letters,
  digits and `_`, starts with a letter or `_`, and may not come twice.
- For a list argument (marked "list" below), pass one JSON object instead
  of words. Some also take a plain string: `run_skillie`'s
  `arguments=value` (one argument), `compose_email`'s `to=a@example.com`,
  `set_tool_rights`'s `rights="a=allow,b=block"`.
- Options: `--socket <path>` reaches another skil.li's tools;
  `--run <id>` is for skil.li's own agents.

| Exit | Meaning | Where the text goes |
| --- | --- | --- |
| 0 | Done | The answer on standard output |
| 1 | Not done: declined, refused, failed, unknown tool, skil.li not running | Why, on standard error (first line first) |
| 2 | The call is written wrong (no tool, a word that is not `name=value`, bad JSON, unknown option) | Usage on standard error |

```bash
if said=$("$SKILLI_CLI" call run_shortcut name="Morning Routine" 2>&1); then
  echo "Done: $said"
else
  echo "Not done: ${said%%$'\n'*}"
fi
```

### Approvals

A skillie's call is treated as an outside agent's (when an agent's
`run_skillie` started the skillie, as that agent's: only the tools its run
has, never `list_tool_rights` or `set_tool_rights`):

- A tool you blocked is refused.
- Otherwise your rules, the approval mode and the tool's own right decide.
  Ask Every Time: every tool asks. Always Allow: none does. Ask Before
  Changes: the tools marked **reads** below run, and so do light changes
  (marked **light**: opening an app or a link, a draft, a reminder, a
  message you confirm before it goes); the others ask in the card. A link
  `open_url` opens with another scheme than http, https, mailto or System Settings' counts as
  a change.
- Changes to skil.li's own settings ask every time; so do `get_transcript`
  and `recording_followup`, naming the recording (its words leave the
  Mac): no Always, no right or mode makes them silent.
- What sends, deletes or pays is asked again during a `do_in_app` step.
- `@skilli.needsConfirmation` replaces none of these: it asks once, before
  the whole script.

The question shows in the skillie's own card, named after it
([running.md](running.md#while-it-runs)).

### Outside a skillie

From Terminal, `Skilli call` works the same way and reaches the skil.li you
run, starting it if needed:

```bash
"<skil.li's app>/Contents/MacOS/Skilli" call system_info
```

`Skilli mcp` is the same tools as an MCP server on standard input and
output, for Claude Code, Codex and other agents.

## Tools

Every tool skil.li offers, by group. Arguments with `?` are optional.
**reads**: only reads, never changes anything.

<!-- Maintainers: the exact text agents see (descriptions, choices) is in
Sources/Skilli/Tools/SkilliTools.swift, SettingTools.swift and
ToolRightsTools.swift. SkillieDocsTests fails when a tool is missing from this
page: add a line here when you add a tool. -->

### Selection and clipboard

| Tool | What it does | Arguments |
| --- | --- | --- |
| `get_selection` | The text selected in the app in front. reads | |
| `replace_selection` | Replaces the selected text. | `text` |
| `get_clipboard` | The clipboard's text. reads | |
| `set_clipboard` | Copies a text. | `text` |

### Apps, browsers, windows

| Tool | What it does | Arguments |
| --- | --- | --- |
| `get_frontmost_app` | The app in front. reads | |
| `list_apps` | Installed apps. reads | |
| `open_app` | Opens an app. light | `name` |
| `open_url` | Opens a link. light | `url` |
| `update_app` | Updates an app: its own Check for Updates, else the App Store, else Homebrew. Without a name: the app in front. | `name?` |
| `list_tabs` | Open browser tabs. reads | |
| `focus_tab` | Goes to a browser tab. | `title` |
| `search_history` | Searches the browsers' history. reads | `query?` |
| `list_projects` | Recent code projects (Cursor, VS Code, Zed…). reads | |
| `open_project` | Opens a recent project in its editor. | `name`, `editor?` |
| `list_windows` | Open windows. reads | |
| `focus_window` | Brings a window forward. light | `window` |
| `save_window_layout` | Saves where the windows are, under a name. | `name` |
| `apply_window_layout` | Puts a saved layout back. | `name` |

### Menus and the screen

| Tool | What it does | Arguments |
| --- | --- | --- |
| `search_menus` | Searches the front app's menus. reads | `query?` |
| `press_menu` | Chooses a menu item. | `path` |
| `list_ui` | The front window's buttons and fields. reads | |
| `find_ui` | Finds an element by description. reads | `description` |
| `press_ui` | Presses an element. | `id` |
| `set_ui_value` | Fills a field. | `id`, `text` |
| `press_keys` | Sends a key or shortcut to the app in front (`cmd+s`). | `keys` |
| `do_in_app` | Hands a whole goal to "do it here" and waits until it is done. | `goal`, `app?` |

### SI Commands, skillies, actions

| Tool | What it does | Arguments |
| --- | --- | --- |
| `list_commands` | Your SI Commands. reads | |
| `run_command` | Runs an SI Command on a text; returns its answer (nothing pasted). light | `id`, `text` |
| `list_skillies` | Your skillies: title, package, description, arguments. reads | |
| `run_skillie` | Runs a skillie by title; returns what it printed. | `title`, `arguments?` (list) |
| `create_skillie` | Writes a new skillie. `language`: bash, zsh, python, node, swift, ruby. `mode`: compact (default), silent, fullOutput. | `title`, `description?`, `language`, `code`, `mode?`, `arguments?` (list of placeholders), `needs_confirmation?` |
| `run_action` | Runs a skil.li action: a linked app's command (`cleanshot.capture-area`), a text case change. | `id`, `variant?`, `file?` |
| `list_shortcuts` | Your shortcuts in Apple's Shortcuts app. reads | |
| `run_shortcut` | Runs a shortcut; returns its text. | `name`, `input?`, `selection?` |
| `create_app_link` | Adds an app skil.li drives through its documented URL scheme. | `app`, `scheme`, `documentation`, `commands`, `id?`, `minimum_version?`, `note?` |
| `create_skill` | Writes a skill for Ask's agent. | `name`, `description`, `instructions` |
| `start_timer` | Starts a timer in the menu bar. | `duration`, `label` |
| `list_timers` | Running timers. reads | |
| `cancel_timer` | Cancels a timer. | `label` |

### Calendar, reminders, contacts, messages

| Tool | What it does | Arguments |
| --- | --- | --- |
| `list_events` | Your calendars' events. reads | `from?`, `to?`, `query?` |
| `create_event` | Adds an event. | `title`, `start`, `end?`, `calendar?`, `location?`, `notes?`, `url?`, `alert_minutes?`, `repeat?` |
| `update_event` | Changes an event. | `id`, `title?`, `start?`, `end?`, `location?`, `notes?` |
| `delete_event` | Deletes an event. | `id` |
| `list_reminders` | Your reminders. reads | `list?`, `query?`, `due_before?`, `completed?` |
| `create_reminder` | Adds a reminder. light | `title`, `due?`, `notes?`, `list?`, `priority?`, `repeat?`, `url?` |
| `update_reminder` | Changes a reminder. | `id`, `done?`, `title?`, `due?`, `list?`, `priority?`, `notes?` |
| `delete_reminder` | Deletes a reminder. | `id` |
| `search_contacts` | Finds people in your contacts. reads | `query` |
| `compose_email` | Opens a new mail, not sent. light | `to` (list), `subject?`, `body?` |
| `send_message` | Sends a message in Slack or Discord, after you confirm who. light | `app`, `to`, `text` |

### GitHub

| Tool | What it does | Arguments |
| --- | --- | --- |
| `list_pull_requests` | Your open pull requests and reviews, by group (ready, blocked, waiting, testing). reads | `group?`, `query?` |
| `list_github_notifications` | Your unread GitHub notifications. reads | `query?` |
| `merge_pull_request` | Merges a pull request. | `pull_request` |
| `update_pull_request_branch` | Updates a pull request's branch. | `pull_request` |
| `mark_github_notification_read` | Marks a notification read. light | `id` |

### The Mac

| Tool | What it does | Arguments |
| --- | --- | --- |
| `system_info` | Battery, free disk, memory, load, Wi-Fi, IP address, uptime, macOS version. reads | |
| `run_mac_command` | A Mac command (lock, sleep, dark mode, `arrangeWindows`, empty the Trash…) or a window placement (`window.leftHalf`). | `command` |
| `keep_awake` | Keeps the Mac awake, longer, or stops. | `minutes?`, `more?`, `until?`, `sleep?` |
| `set_volume` | Sets the volume. | `percent` |
| `list_audio_devices` | Speakers and microphones. reads | |
| `set_audio_device` | Switches the output or input. | `device`, `kind?` |
| `list_bluetooth_devices` | Paired Bluetooth devices. reads | |
| `connect_bluetooth_device` | Connects or disconnects one. | `device`, `action?` |
| `list_processes` | Running processes. reads | `query?` |
| `quit_process` | Quits a process. | `pid`, `force?` |
| `brew_search` | Searches Homebrew. reads | `query?` |
| `brew_install` | Installs with Homebrew. | `name`, `cask?` |
| `brew_upgrade` | Upgrades with Homebrew. | `name?` |

### Meeting recorder

| Tool | What it does | Arguments |
| --- | --- | --- |
| `record_meeting` | Opens the Record card; waits for ↩ (started) or esc. light | `title?` |
| `import_recording` | Makes a recording of a sound or video file (its sound copied, transcribed on the Mac, voices told apart); the file stays where it is. | `path` |
| `recording_status` | The recording on now. reads | |
| `pause_recording` | Pauses it. | |
| `resume_recording` | Resumes it. | |
| `stop_recording` | Stops it; the transcript is made on the Mac. | |
| `set_recording_source` | Turns the microphone, the Mac's sound, the webcam or the screen on or off from now on (Record card open or recording). | `source`, `on` |
| `list_recordings` | The recordings, newest first: id (the folder's name), title, date, length, state, summary and chapters. No words. reads | |
| `get_transcript` | A recording's transcript, as `transcript.md` has it; asked every time, the recording named. reads | `recording?` (an id or a title; empty: the newest) |
| `recording_followup` | What its window's ⌘K does with your SI: `summary`, `chapters`, `action_items` (to Reminders), `recap_mail` (a mail opens, you send it), `ask` (with `question`); asked every time. | `action`, `recording?`, `question?` |

### Snippets and your own tools

| Tool | What it does | Arguments |
| --- | --- | --- |
| `list_snippets` | Your snippets. reads | |
| `insert_snippet` | Types a snippet at the caret. | `name` |

Your own tools (webhooks, Settings → Tools) are offered under the names you
gave them.

### skil.li's settings

Each change asks in the card, every time.

| Tool | What it does | Arguments |
| --- | --- | --- |
| `get_settings` | Reads the settings (secrets only as set or not). reads | `pane?` |
| `set_setting` | Changes one setting. | `pane?`, `setting`, `value`, `change?` |
| `set_alias` | Gives a launcher item an alias. | `alias`, `item`, `kind?` |
| `remove_alias` | Removes an alias. | `alias` |
| `create_quicklink` | Adds a quicklink. | `name`, `url`, `keyword?` |
| `update_quicklink` | Changes a quicklink. | `name`, `new_name?`, `url?`, `keyword?` |
| `delete_quicklink` | Deletes a quicklink. | `name` |
| `create_snippet` | Adds a snippet. | `name`, `text`, `keyword?` |
| `update_snippet` | Changes a snippet. | `name`, `new_name?`, `text?`, `keyword?` |
| `delete_snippet` | Deletes a snippet. | `name` |
| `add_shortcut` | Binds a key to an action. | `action`, `keys` |
| `change_shortcut` | Changes a key. | `keys`, `new_keys` |
| `remove_shortcut` | Removes a key. | `keys` |
| `list_scheduled_asks` | Asks on a schedule. reads | |
| `add_scheduled_ask` | Asks your SI something on a schedule. | `when`, `ask` |
| `pause_scheduled_ask` | Pauses or resumes one. | `ask`, `paused?` |
| `remove_scheduled_ask` | Removes one. | `ask` |
| `list_tool_rights` | The approval mode, your rules, each tool's right. reads | `server?`, `search?` |
| `set_tool_rights` | Sets tools' rights (`tool=right`: default, ask, allow, block). | `server`, `rights` (list) |

### Talking to you

| Tool | What it does | Arguments |
| --- | --- | --- |
| `ask_user` | Asks you a question in the card; returns the answer. | `question`, `options?` (list) |
| `notify` | Shows a short note in the card. | `message` |
| `approve` | Claude Code's permission prompt for another server's tool. Offered only when an Act command's agent started the skillie; not meant to be called from a skillie. | `tool_name`, `input` |

## `skilli://` links

`open` a link from the script: it returns at once, skil.li does the rest.

| Link | What it runs |
| --- | --- |
| `skilli://run/<entry id>` | Any launcher row, by its id: `cmd:emoji`, `system:keepAwake`, `system:link:cleanshot.capture-area`, `system:shortcut:<id>`. ⌘K → Copy Link on a row gives its link. |
| `skilli://skillie/<path>?arg=…` | A skillie, by its path in the skillies folder, arguments in order. |
| `skilli://quicklink/<keyword>?q=…` | A quicklink, with its query. |
| `skilli://layout/<id>` | A saved window layout. |
| `skilli://do?app=<app>&goal=<goal>` | "Do it here" toward a goal (percent-encoded). Several run one after the other, in order. |
| `skilli://record?title=…` | The Record card (nothing records before ↩). |
| `skilli://record/pause`, `…/resume`, `…/stop` | Pauses, resumes or stops the recording on now; asked every time, no Always. |
| `skilli://record/import?file=…` | The Import panel, at that file (nothing imported before ↩). |
| `skilli://record/open?recording=…&at=…` | A recording's window (by its id or title), playing from `at` seconds. |
| `skilli://record/summary?recording=…`, `…/chapters`, `…/actions`, `…/recap`, `…/ask?question=…` | What its window's ⌘K does with your SI; asked every time, the recording named, no Always. |
| `skilli://skillies/import?url=…` | Shows a skillie from the web before Add. |
| `skilli://apps/import?url=…` | Shows an app file before Add. |

A link can come from any app or web page, so what could change the Mac,
type, or run your code asks in the card first; Always in that card lets
links run it at once (not for a skillie with `needsConfirmation`, nor for
the recorder). Opening, reading and placing windows run at once.
The rules are in `SkilliLink.asksFirst` (`Sources/SkilliCore/SkilliLink.swift`).
