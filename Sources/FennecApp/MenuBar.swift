import AppKit
import FennecCore
import ServiceManagement

@MainActor
final class MenuBar: NSObject {
    enum Status: Equatable {
        case starting
        case downloading(percent: Int)
        case idle
        case listening
        case working
        case problem(String)

        var title: String {
            switch self {
            case .starting: return "Loading speech model…"
            case .downloading(let percent): return "Downloading speech model… \(percent)%"
            case .idle: return "Ready"
            case .listening: return "Listening"
            case .working: return "Transcribing"
            case .problem(let message): return message
            }
        }

        var glyph: MenuBarGlyph.Style {
            switch self {
            case .idle: return .idle
            case .listening: return .listening
            case .starting, .downloading, .working: return .working
            case .problem: return .attention
            }
        }
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let hintMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "Launch at login", action: nil, keyEquivalent: "")
    private var status: Status?

    var hotkeyName = Hotkey.rightOption.displayName {
        didSet { hintMenuItem.title = "Hold \(hotkeyName) to dictate" }
    }

    var onCopyLastTranscript: (() -> Void)?
    var onEditDictionary: (() -> Void)?
    var onEditConfig: (() -> Void)?
    var onReloadConfig: (() -> Void)?
    var onRevealLog: (() -> Void)?
    var onRequestPermissions: (() -> Void)?
    var onQuit: (() -> Void)?

    override init() {
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusMenuItem.isEnabled = false
        hintMenuItem.isEnabled = false
        hintMenuItem.title = "Hold \(hotkeyName) to dictate"
        menu.addItem(statusMenuItem)
        menu.addItem(hintMenuItem)
        menu.addItem(.separator())
        add(menu, "Copy last transcript", #selector(copyLast))
        add(menu, "Edit dictionary…", #selector(editDictionary))
        add(menu, "Edit config…", #selector(editConfig))
        add(menu, "Reload config", #selector(reloadConfig))
        menu.addItem(.separator())
        launchAtLoginItem.action = #selector(toggleLaunchAtLogin)
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        add(menu, "Permissions…", #selector(permissions))
        add(menu, "Reveal log", #selector(revealLog))
        menu.addItem(.separator())
        add(menu, "About Fennec", #selector(about))
        add(menu, "Quit Fennec", #selector(quit), key: "q")
        statusItem.menu = menu
        update(.starting)
    }

    func update(_ status: Status) {
        guard status != self.status else { return }
        let glyphChanged = status.glyph != self.status?.glyph
        self.status = status
        statusMenuItem.title = status.title
        statusItem.button?.toolTip = "Fennec: \(status.title)"
        if glyphChanged {
            statusItem.button?.image = MenuBarGlyph.image(status.glyph)
        }
    }

    private func add(_ menu: NSMenu, _ title: String, _ selector: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc private func copyLast() { onCopyLastTranscript?() }
    @objc private func editDictionary() { onEditDictionary?() }
    @objc private func editConfig() { onEditConfig?() }
    @objc private func reloadConfig() { onReloadConfig?() }
    @objc private func permissions() { onRequestPermissions?() }
    @objc private func revealLog() { onRevealLog?() }
    @objc private func quit() { onQuit?() }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func about() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Fennec \(fennecVersion)"
        alert.informativeText = """
            On-device push-to-talk dictation. Hold \(hotkeyName), speak, release.

            Speech recognition powered by Desert Ant Labs.
            Copyright © 2026 Jam-Sw. Source-available under the PolyForm Strict License.
            """
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Desert Ant Labs")
        if alert.runModal() == .alertSecondButtonReturn, let url = URL(string: "https://desertant.com") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension MenuBar: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
