//
//  QuickAddApp.swift
//  QuickAdd
//
//  Created by Alex on 8/22/26.
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
struct QuickAddApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            EmptyView()
        }
        .defaultLaunchBehavior(.suppressed)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: QuickAddPanelController?
    private var globalHotKey: GlobalHotKey?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panelController = QuickAddPanelController()
        self.panelController = panelController
        configureStatusItem()

        globalHotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_A),
            modifiers: UInt32(controlKey | cmdKey)
        ) { [weak panelController] in
            panelController?.toggle()
        }
    }

    @objc private func showQuickAdd(_ sender: Any?) {
        panelController?.present()
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(
            systemSymbolName: "checkmark.circle",
            accessibilityDescription: "QuickAdd"
        )
        image?.isTemplate = true
        statusItem.button?.image = image

        let menu = NSMenu()
        let quickAddItem = NSMenuItem(
            title: "Quick Add",
            action: #selector(showQuickAdd(_:)),
            keyEquivalent: "a"
        )
        quickAddItem.keyEquivalentModifierMask = [.control, .command]
        quickAddItem.target = self
        menu.addItem(quickAddItem)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit QuickAdd",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        statusItem.menu = menu
        self.statusItem = statusItem
    }
}
