import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var model: UsageViewModel!
    private var cancellables = Set<AnyCancellable>()
    private var appearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = UsageViewModel()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])

            // Redraw when the menu bar switches between light and dark.
            appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] _, _ in
                DispatchQueue.main.async { self?.updateStatusItem() }
            }
        }

        let hosting = NSHostingController(rootView: UsageMenuView(model: model))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true

        // `objectWillChange` fires before the new value is stored, so the
        // update runs on the next main-loop pass.
        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)

        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button, let model else { return }

        button.image = GaugeRenderer.image(for: model.gauge)

        if model.showPercentage {
            button.imagePosition = .imageLeading
            button.attributedTitle = NSAttributedString(
                string: " " + model.menuBarText,
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium)]
            )
        } else {
            button.imagePosition = .imageOnly
            button.attributedTitle = NSAttributedString(string: "")
        }

        button.toolTip = model.tooltip
        button.setAccessibilityLabel("Claude usage \(model.menuBarText) remaining")
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            model.refreshIfStale()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
