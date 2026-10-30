import AppKit
import SwiftUI

@MainActor
final class StatusBarController {
    private let store: Store
    private let settings: Settings
    private var items: [Module: ModuleItem] = [:]

    init(store: Store, settings: Settings) {
        self.store = store
        self.settings = settings
        sync()
    }

    /// Creates or removes status items so they match the enabled modules.
    func sync() {
        // A new status item is placed to the left of existing ones, so create right-to-left.
        for module in Module.allCases.reversed() {
            let wanted = settings.isEnabled(module)
            if wanted, items[module] == nil {
                items[module] = ModuleItem(module: module, store: store)
            } else if !wanted, let item = items.removeValue(forKey: module) {
                item.remove()
            }
        }
        if items.isEmpty {
            // Never leave the user without a way back into the app.
            items[.cpu] = ModuleItem(module: .cpu, store: store)
        }
        store.activeModules = Set(items.keys)
        render()
    }

    func render() {
        for item in items.values {
            item.render(showLabels: settings.showLabels, colored: settings.menuBarStyle == .color)
        }
    }

    /// Opens each panel in turn and reports what's on screen (see `--selftest`).
    func selfTest(captureTo directory: URL?) -> [String] {
        if let directory { try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        return Module.allCases.compactMap { items[$0] }.map { $0.selfTest(captureTo: directory) }
    }
}

@MainActor
private final class ModuleItem: NSObject, NSPopoverDelegate {
    let module: Module
    private let store: Store
    private let statusItem: NSStatusItem
    private lazy var popover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let host = NSHostingController(rootView: PanelView(module: module, store: store))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        return popover
    }()

    private var usesProcesses: Bool { module == .cpu || module == .memory }

    init(module: Module, store: Store) {
        self.module = module
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.autosaveName = "chrono.\(module.rawValue)"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.setAccessibilityLabel("Chrono \(module.title)")
        // Colored images are drawn for one appearance, so redraw as soon as the menu bar flips
        // between light and dark (e.g. a wallpaper change) instead of waiting for the next tick.
        appearanceObservation = statusItem.button?.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.rerender() }
        }
    }

    private var renderedSignature: String?
    private var appearanceObservation: NSKeyValueObservation?
    private var lastOptions = (showLabels: true, colored: true)

    func render(showLabels: Bool, colored: Bool) {
        lastOptions = (showLabels, colored)
        let dark = statusItem.button?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let ink = colored ? MenuBarInk(colored: true, dark: dark) : .template
        // Rendering goes through SwiftUI and the menu bar server, so skip it when nothing visible changed.
        let signature = MenuBarLabel(module: module, store: store, showLabels: showLabels, ink: ink).signature
        guard signature != renderedSignature else { return }
        renderedSignature = signature
        statusItem.button?.image = MenuBarRenderer.image(for: module, store: store, showLabels: showLabels, ink: ink)
    }

    private func rerender() {
        render(showLabels: lastOptions.showLabels, colored: lastOptions.colored)
    }

    func remove() {
        if popover.isShown { popover.performClose(nil) }
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func toggle() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            if usesProcesses {
                store.processConsumers += 1
                store.refresh()
                // Per-process CPU is a delta between two samples, so take a second one right away
                // instead of showing "Sampling…" until the next regular tick.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.store.refresh() }
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func selfTest(captureTo directory: URL?) -> String {
        let button = statusItem.button
        let frame = button?.window?.frame ?? .zero
        let image = button?.image?.size ?? .zero
        toggle()
        let shown = popover.isShown
        let panel = popover.contentViewController?.view.fittingSize ?? .zero
        if let directory {
            // Let the popover finish layout and animate in, then draw its window's whole view tree.
            RunLoop.main.run(until: Date().addingTimeInterval(0.8))
            if let view = popover.contentViewController?.view.window?.contentView?.superview,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: directory.appendingPathComponent("live-\(module.rawValue).png"))
            }
        }
        toggle()
        return "\(module.title): visible=\(statusItem.isVisible) bar=\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height)) "
            + "image=\(Int(image.width))x\(Int(image.height)) popover=\(shown) \(Int(panel.width))x\(Int(panel.height))"
    }

    func popoverDidClose(_ notification: Notification) {
        if usesProcesses { store.processConsumers = max(0, store.processConsumers - 1) }
    }
}
