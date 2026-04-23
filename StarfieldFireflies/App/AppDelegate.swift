// ============================================
// App/AppDelegate.swift
// StarfieldFireflies — 星空与萤火
// ============================================

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Future: window management, menu customization
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Future: cleanup resources (audio engine, Metal buffers)
    }
}
