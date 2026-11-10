//
//  A2DPHook.swift
//  BlueForge
//
//  Hook strategies for the system A2DP path.
//
//  Honest capability matrix on jailed iOS (matches worse_query's own scope):
//    + Filesystem introspection of bluetoothd state (sandbox extension escape).
//    + Runtime observation of AVAudioSession routes (public API).
//    - Code injection into bluetoothd — requires a jailbreak runtime; neither
//      worse_query nor this app can do that on iOS 26/27. The strategy exists
//      here so the failure is explicit and documented instead of silent.
//

import Foundation
import AVFoundation
import Combine

/// Strategies the app can attach to the system's A2DP path.
enum A2DPHookStrategy: String, CaseIterable, Identifiable {
    case systemStateEnumeration = "System state enumeration"
    case sessionRouteObserver = "AVAudioSession route observer"
    case bluetoothDInjection = "bluetoothd codec override (jailbreak only)"

    var id: String { rawValue }

    var feasibleJailed: Bool {
        self != .bluetoothDInjection
    }

    var detail: String {
        switch self {
        case .systemStateEnumeration:
            return "Consume sandbox extensions (worse_query technique) to read bluetoothd preference/state containers."
        case .sessionRouteObserver:
            return "Watch AVAudioSession route changes to see when the system activates an A2DP sink route."
        case .bluetoothDInjection:
            return "Inject an ElleKit hook dylib into bluetoothd to re-write A2DP SEP negotiation so LDAC/aptX get selected. Never possible jailed iOS 26/27."
        }
    }
}

struct A2DPHookResult: Identifiable {
    let id = UUID()
    let strategy: A2DPHookStrategy
    let success: Bool
    let message: String
}

enum A2DPHookError: LocalizedError {
    case requiresJailbreak

    var errorDescription: String? {
        switch self {
        case .requiresJailbreak:
            return "Code injection into bluetoothd requires a jailbroken runtime. worse_query grants file access only; it is not and never will be a jailbreak."
        }
    }
}
    }
}

/// Runs the feasible hooks; makes the infeasible one fail loudly with the reason.
@MainActor
final class A2DPHookCoordinator: ObservableObject {
    @Published var results: [A2DPHookResult] = []
    @Published var routeLog: [String] = []

    private var routeObserver: NSObjectProtocol?

    /// Activate the two hooks that work without a jailbreak, and surface the
    /// exact reason the third cannot.
    func activateAll() {
        results.removeAll()
        results.append(activateSystemStateEnumeration())
        results.append(activateSessionRouteObserver())
        results.append(activateBluetoothDInjection())
    }

    private func activateSystemStateEnumeration() -> A2DPHookResult {
        A2DPHookResult(strategy: .systemStateEnumeration,
                       success: true,
                       message: "Sandbox enumeration hook armed — run the probe to read bluetoothd state.")
    }

    private func activateSessionRouteObserver() -> A2DPHookResult {
        if routeObserver != nil {
            return A2DPHookResult(strategy: .sessionRouteObserver, success: true,
                                  message: "Already observing route changes.")
        }
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleRouteChange(note)
        }
        handleRouteChange(nil)
        return A2DPHookResult(strategy: .sessionRouteObserver, success: true,
                              message: "Observing AVAudioSession route changes.")
    }

    private func activateBluetoothDInjection() -> A2DPHookResult {
        if JailbreakDetector.isJailbroken() {
            return A2DPHookResult(strategy: .bluetoothDInjection,
                                  success: false,
                                  message: "Jailbreak runtime detected, but the injection payload is part of a separate licensed build — see docs/SANDBOX_A2DP.md.")
        }
        return A2DPHookResult(strategy: .bluetoothDInjection,
                              success: false,
                              message: A2DPHookError.requiresJailbreak.localizedDescription)
    }

    private func handleRouteChange(_ note: Notification?) {
        let session = AVAudioSession.sharedInstance()
        var lines: [String] = []
        if let note {
            let reasonRaw = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue ?? 0
            lines.append("reason=\(reasonRaw)")
        }
        for output in session.currentRoute.outputs {
            if output.portType == .bluetoothA2DP || output.portType == .bluetoothLE {
                lines.append("A2DP route: \(output.portName) (\(output.portType.rawValue))")
            }
        }
        routeLog.append(lines.joined(separator: " · "))
        if routeLog.count > 50 {
            routeLog.removeFirst(routeLog.count - 50)
        }
    }

    deinit {
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
        }
    }
}

/// Detection kept deliberately minimal: presence of common root markers.
enum JailbreakDetector {
    static let markers = [
        "/Applications/Cydia.app",
        "/usr/lib/ellekit.dylib",
        "/usr/lib/TweakInject.dylib",
        "/private/var/jb",
        "/var/jb"
    ]

    static func isJailbroken() -> Bool {
        markers.contains { FileManager.default.fileExists(atPath: $0) }
    }
}
