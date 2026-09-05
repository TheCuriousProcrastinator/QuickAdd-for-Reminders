//
//  QuickAddPanelController.swift
//  QuickAdd
//

import AppKit
import SwiftUI

private final class QuickAddHostingView<Content: View>: NSHostingView<Content> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
}

final class QuickAddPanelController {
    private static let panelWidth: CGFloat = 580
    private let panel: NSPanel
    private var didBecomeKeyObserver: NSObjectProtocol?
    private var hasInitialPlacement = false

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 1),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.contentView = QuickAddHostingView(rootView: makeContentView())
    }

    func toggle() {
        if isActivelyPresented {
            hide()
        } else {
            present()
        }
    }

    func present() {
        guard !isActivelyPresented else { return }
        show()
    }

    private var isActivelyPresented: Bool {
        panel.isVisible && panel.isKeyWindow && NSApp.isActive
    }

    private func show() {
        panel.contentView = QuickAddHostingView(rootView: makeContentView())
        resizeToFitContent(centerOnScreen: !hasInitialPlacement)
        hasInitialPlacement = true
        observePanelBecomingKey()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func makeContentView() -> ContentView {
        ContentView(
            onSubmit: { [weak self] in self?.hide() },
            onEscape: { [weak self] in self?.hide() },
            onLayoutChange: { [weak self] in self?.resizeToFitContentAfterLayout() }
        )
    }

    private func resizeToFitContentAfterLayout() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible else { return }
            self.resizeToFitContent()
        }
    }

    private func resizeToFitContent(centerOnScreen: Bool = false) {
        guard let contentView = panel.contentView else { return }
        let fittingSize = contentView.fittingSize
        guard fittingSize.width > 0, fittingSize.height > 0 else { return }
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        panel.setContentSize(NSSize(width: Self.panelWidth, height: ceil(fittingSize.height)))
        if centerOnScreen {
            centerOnCurrentScreen()
        } else {
            panel.setFrameOrigin(NSPoint(x: topLeft.x, y: topLeft.y - panel.frame.height))
        }
    }

    private func hide() {
        panel.orderOut(nil)
    }

    private func observePanelBecomingKey() {
        if let didBecomeKeyObserver {
            NotificationCenter.default.removeObserver(didBecomeKeyObserver)
        }

        didBecomeKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                NotificationCenter.default.post(
                    name: .quickAddTitleFocusRequested,
                    object: self.panel
                )
            }
        }
    }

    private func centerOnCurrentScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main

        guard let visibleFrame = screen?.visibleFrame else { return }
        let origin = NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.midY - panel.frame.height / 2
        )
        panel.setFrameOrigin(origin)
    }
}
