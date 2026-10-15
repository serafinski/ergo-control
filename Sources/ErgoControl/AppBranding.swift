import AppKit

enum AppBranding {
    static let menuMark: NSImage = {
        let image = Bundle.main.image(forResource: "ErgoMarkTemplate")
            ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil) ?? NSImage()
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()

    static let appIcon: NSImage = {
        Bundle.main.image(forResource: "AppIcon") ?? menuMark
    }()
}
