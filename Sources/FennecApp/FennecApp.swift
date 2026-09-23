import AppKit

@main
struct FennecApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let controller = AppController()
        controller.start()
        application.run()
    }
}
