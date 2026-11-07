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
    private var lastAppearanceIsDark: Bool?
    private var lastRendered: RenderedState?

    /// Everything that affects what the status item looks like. Redraws are
    /// skipped when this is unchanged.
    private struct RenderedState: Equatable {
        let gauge: Gauge
        let text: String?
        let tooltip: String
        let isDark: Bool
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = UsageViewModel()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])

            // Redraw only when the menu bar actually switches between light
            // and dark. Updating the button's image or title re-sends this KVO
            // notification even though the appearance is unchanged, so reacting
            // to every notification would redraw in an endless loop.
            appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] button, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    let isDark = Self.isDark(button.effectiveAppearance)
                    guard isDark != self.lastAppearanceIsDark else { return }
                    self.lastAppearanceIsDark = isDark
                    self.updateStatusItem()
                }
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

        let state = RenderedState(
            gauge: model.gauge,
            text: model.showPercentage ? model.menuBarText : nil,
            tooltip: model.tooltip,
            isDark: Self.isDark(button.effectiveAppearance)
        )
        guard state != lastRendered else { return }
        lastRendered = state

        button.image = GaugeRenderer.image(for: state.gauge)

        if let text = state.text {
            button.imagePosition = .imageLeading
            button.attributedTitle = NSAttributedString(
                string: " " + text,
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium)]
            )
        } else {
            button.imagePosition = .imageOnly
            button.attributedTitle = NSAttributedString(string: "")
        }

        button.toolTip = state.tooltip
        button.setAccessibilityLabel("Claude usage \(model.menuBarText) remaining")
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
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
