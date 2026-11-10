//
//  BlueForgeApp.swift
//  BlueForge
//
//  Entry point. Registers as an audio-document handler so any app can hand
//  media to BlueForge via the share sheet / "Open in BlueForge"
//  (CFBundleDocumentTypes: public.audio). Opened files become the streaming
//  source in ContentView.
//

import SwiftUI

extension Notification.Name {
    static let blueforgeIngestMedia = Notification.Name("blueforge.ingestMedia")
}

@main
struct BlueForgeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    NotificationCenter.default.post(name: .blueforgeIngestMedia, object: url)
                }
        }
    }
}
