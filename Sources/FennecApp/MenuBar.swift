import AppKit
import FennecCore

@MainActor
final class MenuBar: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusMenuItem = NSMenuItem(title: "Idle", action: nil, keyEquivalent: "")

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
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        add(menu, "Copy last transcript", #selector(copyLast))
        add(menu, "Edit dictionary", #selector(editDictionary))
        add(menu, "Edit config", #selector(editConfig))
        add(menu, "Reload config", #selector(reloadConfig))
        menu.addItem(.separator())
        add(menu, "Permissions", #selector(permissions))
        add(menu, "Reveal log", #selector(revealLog))
        menu.addItem(.separator())
        add(menu, "About Fennec", #selector(about))
        add(menu, "Quit Fennec", #selector(quit))
        statusItem.menu = menu
        statusItem.button?.title = "Fennec"
    }

    func update(state: String) {
        statusMenuItem.title = state
        statusItem.button?.toolTip = "Fennec: \(state)"
    }

    private func add(_ menu: NSMenu, _ title: String, _ selector: Selector) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
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

    @objc private func about() {
        let alert = NSAlert()
        alert.messageText = "Fennec \(fennecVersion)"
        alert.informativeText = "On-device push-to-talk dictation. Hold Right Option, speak, release.\n\nPowered by Desert Ant Labs."
        alert.runModal()
    }
}
