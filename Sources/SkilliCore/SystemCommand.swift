import Foundation

/// Mac commands from the launcher, Ask and agents: lock, sleep, appearance,
/// Trash, hidden files, disks, staying awake, restart.
public enum SystemCommand: String, CaseIterable, Sendable {
    case lockScreen
    case sleep
    case sleepDisplays
    case toggleDarkMode
    case keepAwake
    case toggleHiddenFiles
    case ejectDisks
    case emptyTrash
    case restart
    case shutDown
    case logOut
    case playPause
    case nextTrack
    case previousTrack
    case volumeUp
    case volumeDown
    case mute
    case speedTest
    case pickColor
    case pasteLatestScreenshot
    case systemInfo
    case cleanKeyboard
    case quitAllApps
    case quitOtherApps
    case hideOtherApps
    case showAllApps
    case toggleMicrophone
    case wifiOn
    case wifiOff
    case showDesktop

    public var title: String {
        switch self {
        case .lockScreen: "Lock Screen"
        case .sleep: "Sleep"
        case .sleepDisplays: "Sleep Displays"
        case .toggleDarkMode: "Toggle Dark Mode"
        case .keepAwake: "Keep Awake"
        case .toggleHiddenFiles: "Toggle Hidden Files"
        case .ejectDisks: "Eject All Disks"
        case .emptyTrash: "Empty Trash"
        case .restart: "Restart"
        case .shutDown: "Shut Down"
        case .logOut: "Log Out"
        case .playPause: "Play / Pause"
        case .nextTrack: "Next Track"
        case .previousTrack: "Previous Track"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .mute: "Mute / Unmute"
        case .speedTest: "Test Internet Speed"
        case .pickColor: "Pick a Color"
        case .pasteLatestScreenshot: "Paste Latest Screenshot"
        case .systemInfo: "System Info"
        case .cleanKeyboard: "Clean Keyboard"
        case .quitAllApps: "Quit All Apps"
        case .quitOtherApps: "Quit Other Apps"
        case .hideOtherApps: "Hide Other Apps"
        case .showAllApps: "Show All Apps"
        case .toggleMicrophone: "Mute / Unmute Microphone"
        case .wifiOn: "Turn Wi-Fi On"
        case .wifiOff: "Turn Wi-Fi Off"
        case .showDesktop: "Show Desktop"
        }
    }

    /// Other words people type, in English and French.
    public var keywords: [String] {
        switch self {
        case .lockScreen: ["lock", "verrouiller", "verrouillage"]
        case .sleep: ["veille", "suspendre"]
        case .sleepDisplays: ["screen off", "écran", "veille écran"]
        case .toggleDarkMode: ["dark", "light", "appearance", "sombre", "clair", "apparence"]
        case .keepAwake: ["caffeinate", "awake", "coffee", "amphetamine", "éveillé", "café"]
        case .toggleHiddenFiles: ["hidden", "dotfiles", "cachés", "fichiers cachés"]
        case .ejectDisks: ["eject", "unmount", "éjecter"]
        case .emptyTrash: ["trash", "bin", "corbeille", "vider"]
        case .restart: ["reboot", "redémarrer"]
        case .shutDown: ["power off", "éteindre"]
        case .logOut: ["sign out", "déconnexion", "fermer la session"]
        case .playPause: ["play", "pause", "music", "spotify", "musique", "lecture", "reprendre"]
        case .nextTrack: ["next", "skip", "suivant", "chanson suivante", "morceau suivant"]
        case .previousTrack: ["previous", "back", "précédent", "chanson précédente"]
        case .volumeUp: ["louder", "sound", "plus fort", "monter le son", "son"]
        case .volumeDown: ["quieter", "sound", "moins fort", "baisser le son", "son"]
        case .mute: ["silence", "sound off", "couper le son", "muet"]
        case .speedTest: ["speedtest", "network", "wifi", "bandwidth", "connexion", "débit", "réseau"]
        case .pickColor: ["color picker", "eyedropper", "hex", "couleur", "pipette"]
        case .pasteLatestScreenshot: ["screenshot", "last screenshot", "screen capture", "capture d'écran", "dernière capture", "coller la capture", "capture"]
        case .systemInfo: ["battery", "disk", "memory", "ip", "uptime", "batterie", "disque", "mémoire", "infos"]
        case .cleanKeyboard: ["clean", "wipe", "lock keyboard", "nettoyer", "clavier", "bloquer le clavier"]
        case .quitAllApps: ["quit everything", "close all apps", "quitter toutes les apps", "fermer toutes les applications", "tout fermer"]
        case .quitOtherApps: ["quit others", "close other apps", "quitter les autres", "fermer les autres apps", "garder seulement"]
        case .hideOtherApps: ["hide others", "focus", "masquer les autres", "cacher les autres apps"]
        case .showAllApps: ["unhide", "show all", "afficher tout", "tout afficher", "démasquer"]
        case .toggleMicrophone: ["mic", "mute mic", "microphone", "micro", "couper le micro", "remettre le micro", "muet micro"]
        case .wifiOn: ["wifi", "wi-fi", "wireless", "allumer le wifi", "activer le wifi", "remettre le wifi"]
        case .wifiOff: ["wifi", "wi-fi", "wireless", "couper le wifi", "désactiver le wifi", "éteindre le wifi", "hors ligne", "offline"]
        case .showDesktop: ["desktop", "bureau", "afficher le bureau", "montrer le bureau", "voir le bureau", "hide windows", "écarter les fenêtres"]
        }
    }

    /// What it does, for the decision model choosing it from a request.
    public var description: String {
        switch self {
        case .lockScreen: "Lock the screen now"
        case .sleep: "Put the Mac to sleep"
        case .sleepDisplays: "Turn the displays off, the Mac stays on"
        case .toggleDarkMode: "Switch between dark and light appearance"
        case .keepAwake: "Keep the Mac and its display awake, now, for a while or until a time (pas de veille jusqu'à 18h30, garde le mac allumé une heure), or let them sleep again"
        case .toggleHiddenFiles: "Show or hide hidden files in Finder"
        case .ejectDisks: "Eject every external disk"
        case .emptyTrash: "Empty the Trash, deleting its files for good"
        case .restart: "Restart the Mac"
        case .shutDown: "Shut the Mac down"
        case .logOut: "Log out of this account"
        case .playPause: "Play or pause the music or video playing (Spotify, Music, a browser)"
        case .nextTrack: "Skip to the next song or track"
        case .previousTrack: "Go back to the previous song or track"
        case .volumeUp: "Turn the sound up one step: louder (monte le son, plus fort), no level said"
        case .volumeDown: "Turn the sound down one step: quieter (baisse le son, moins fort), no level said"
        case .mute: "Mute or unmute the sound"
        case .speedTest: "Test the internet connection's speed (download, upload, responsiveness)"
        case .pickColor: "Pick a color anywhere on screen and copy its hex code"
        case .pasteLatestScreenshot: "Paste the most recent screenshot into the app in front (the image itself, from the screenshots folder)"
        case .systemInfo: "Tell the Mac's state: how much battery is left, how much disk space is free, memory used, the Wi-Fi it is on, IP address, how long since it started"
        case .cleanKeyboard: "Turn the keyboard off for a minute to clean or wipe it; a click turns it back on"
        case .quitAllApps: "Quit every open app (each asks to save its work)"
        case .quitOtherApps: "Quit every open app except the one in front"
        case .hideOtherApps: "Hide every app except the one in front"
        case .showAllApps: "Show every hidden app again"
        case .toggleMicrophone: "Mute the microphone, or turn it back on"
        case .wifiOn: "Turn Wi-Fi on when it is off (rallume le wifi); not restart it, not open its settings"
        case .wifiOff: "Turn Wi-Fi off (coupe le wifi): the Mac goes offline unless a cable connects it; not restart it, not open its settings"
        case .showDesktop: "Show the desktop (montre le bureau): every window of every app moves aside; again brings them back"
        }
    }

    public var symbol: String {
        switch self {
        case .lockScreen: "lock.fill"
        case .sleep: "moon.zzz.fill"
        case .sleepDisplays: "display"
        case .toggleDarkMode: "circle.lefthalf.filled"
        case .keepAwake: "cup.and.saucer.fill"
        case .toggleHiddenFiles: "eye"
        case .ejectDisks: "eject.fill"
        case .emptyTrash: "trash.fill"
        case .restart: "arrow.clockwise"
        case .shutDown: "power"
        case .logOut: "rectangle.portrait.and.arrow.right"
        case .playPause: "playpause.fill"
        case .nextTrack: "forward.fill"
        case .previousTrack: "backward.fill"
        case .volumeUp: "speaker.wave.3.fill"
        case .volumeDown: "speaker.wave.1.fill"
        case .mute: "speaker.slash.fill"
        case .speedTest: "gauge.with.dots.needle.67percent"
        case .pickColor: "eyedropper"
        case .pasteLatestScreenshot: "photo.on.rectangle.angled"
        case .systemInfo: "info.circle"
        case .cleanKeyboard: "keyboard"
        case .quitAllApps: "xmark.circle"
        case .quitOtherApps: "xmark.square.fill"
        case .hideOtherApps: "eye.slash"
        case .showAllApps: "macwindow.on.rectangle"
        case .toggleMicrophone: "mic.slash.fill"
        case .wifiOn: "wifi"
        case .wifiOff: "wifi.slash"
        case .showDesktop: "menubar.dock.rectangle"
        }
    }

    /// Asked first in the card: cannot be undone, or closes everything.
    public var needsConfirmation: Bool {
        [.emptyTrash, .restart, .shutDown, .logOut].contains(self)
    }
}
