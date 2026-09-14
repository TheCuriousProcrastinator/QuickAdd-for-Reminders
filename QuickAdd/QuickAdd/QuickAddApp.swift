//
//  QuickAddApp.swift
//  QuickAdd
//
//  Created by Alex on 8/22/26.
//

import AppKit
import Carbon.HIToolbox
import ServiceManagement
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var panelController: QuickAddPanelController?
    private var globalHotKey: GlobalHotKey?
    private var statusItem: NSStatusItem?
    private var launchAtLoginItem: NSMenuItem?
    private var checkForUpdatesItem: NSMenuItem?
    private var isCheckingForUpdates = false

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

    @objc private func toggleLaunchAtLogin(_ sender: Any?) {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled, .requiresApproval:
                try service.unregister()
            case .notRegistered:
                try service.register()
                if service.status == .requiresApproval {
                    let alert = NSAlert()
                    alert.messageText = "Approve QuickAdd at Login"
                    alert.informativeText = "Allow QuickAdd in System Settings → General → Login Items to finish enabling it."
                    alert.addButton(withTitle: "Open Login Items")
                    alert.addButton(withTitle: "Later")
                    if alert.runModal() == .alertFirstButtonReturn {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
            case .notFound:
                showLaunchAtLoginError("macOS could not find this QuickAdd app. Move it to Applications and try again.")
            @unknown default:
                showLaunchAtLoginError("macOS returned an unknown login-item status.")
            }
        } catch {
            showLaunchAtLoginError(error.localizedDescription)
        }
        refreshLaunchAtLoginItem()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshLaunchAtLoginItem()
        refreshCheckForUpdatesItem()
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        refreshCheckForUpdatesItem()

        Task {
            defer {
                isCheckingForUpdates = false
                refreshCheckForUpdatesItem()
            }
            do {
                let release = try await QuickAddUpdateChecker.latestRelease()
                guard let installedVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                      let installed = QuickAddVersion(installedVersion),
                      let latest = QuickAddVersion(release.version) else {
                    throw QuickAddUpdateChecker.CheckError.invalidResponse
                }

                let alert = NSAlert()
                if latest > installed {
                    alert.messageText = "QuickAdd \(release.version) Is Available"
                    alert.informativeText = "You have QuickAdd \(installedVersion). Download the new ZIP from GitHub, then replace your app when you're ready."
                    alert.addButton(withTitle: "Download from GitHub")
                    alert.addButton(withTitle: "Later")
                    if alert.runModal() == .alertFirstButtonReturn,
                       !NSWorkspace.shared.open(release.downloadURL) {
                        showUpdateError("Couldn’t open the GitHub download in your browser.")
                    }
                } else {
                    alert.messageText = "QuickAdd Is Up to Date"
                    alert.informativeText = "You have the latest release (\(installedVersion))."
                    alert.runModal()
                }
            } catch {
                showUpdateError(error.localizedDescription)
            }
        }
    }

    private func refreshCheckForUpdatesItem() {
        checkForUpdatesItem?.title = isCheckingForUpdates ? "Checking for Updates…" : "Check for Updates…"
        checkForUpdatesItem?.isEnabled = !isCheckingForUpdates
    }

    private func showUpdateError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t Check for Updates"
        alert.informativeText = message
        alert.runModal()
    }

    private func refreshLaunchAtLoginItem() {
        guard let launchAtLoginItem else { return }
        let status = SMAppService.mainApp.status
        launchAtLoginItem.title = status == .requiresApproval
            ? "Launch at Login (Approval Needed)"
            : "Launch at Login"
        launchAtLoginItem.state = status == .enabled || status == .requiresApproval ? .on : .off
    }

    private func showLaunchAtLoginError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t Change Launch at Login"
        alert.informativeText = message
        alert.runModal()
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

        let launchAtLoginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        self.launchAtLoginItem = launchAtLoginItem
        refreshLaunchAtLoginItem()

        let checkForUpdatesItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkForUpdatesItem.target = self
        menu.addItem(checkForUpdatesItem)
        self.checkForUpdatesItem = checkForUpdatesItem

        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit QuickAdd",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        menu.delegate = self
        statusItem.menu = menu
        self.statusItem = statusItem
    }
}
