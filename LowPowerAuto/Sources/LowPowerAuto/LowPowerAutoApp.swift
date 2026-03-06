import AppKit
import SwiftUI

@main
struct LowPowerAutoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(viewModel: appDelegate.viewModel)
                .frame(width: 320)
                .padding()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = LowPowerModeViewModel()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "Battery"
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 340, height: 260)
        popover.contentViewController = NSHostingController(rootView: StatusMenuView(viewModel: viewModel))

        self.statusItem = statusItem
        self.popover = popover

        viewModel.start()
        updateStatusTitle()

        viewModel.onStateUpdate = { [weak self] in
            Task { @MainActor in
                self?.updateStatusTitle()
            }
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let popover else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.contentViewController = NSHostingController(rootView: StatusMenuView(viewModel: viewModel))
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }

    private func updateStatusTitle() {
        guard let button = statusItem?.button else { return }

        let iconColor: NSColor = viewModel.lowPowerModeEnabled ? .systemYellow : .white
        let batteryLevel = Double(viewModel.batteryPercent ?? 100) / 100.0

        var image: NSImage?
        if viewModel.isCharging {
            image = NSImage(systemSymbolName: "battery.100.bolt", accessibilityDescription: "Battery charging")
        } else if #available(macOS 13.0, *) {
            image = NSImage(
                systemSymbolName: "battery.100percent",
                variableValue: batteryLevel,
                accessibilityDescription: "Battery level"
            )
        } else {
            image = NSImage(systemSymbolName: "battery.100", accessibilityDescription: "Battery level")
        }

        if let image {
            if #available(macOS 12.0, *) {
                let config = NSImage.SymbolConfiguration(hierarchicalColor: iconColor)
                button.image = image.withSymbolConfiguration(config)
            } else {
                button.image = image
            }
            button.image?.isTemplate = false
        } else {
            button.image = nil
        }

        let percentText: String
        if let batteryPercent = viewModel.batteryPercent {
            percentText = "\(batteryPercent)%"
        } else {
            percentText = "--"
        }

        button.title = " \(percentText)"
    }
}
