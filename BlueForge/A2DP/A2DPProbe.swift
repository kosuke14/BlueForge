//
//  A2DPProbe.swift
//  BlueForge
//
//  A2DP / Bluetooth stack introspection on jailed iOS using the SandEscape
//  primitives (derived from forcequitOS/worse_query, GPL-3.0).
//
//  What this can honestly do on a jailed device:
//    - Enumerate containers (pathleak) that hold Bluetooth stack state.
//    - Consume sandbox extensions to READ that state (pairing records,
//      bluetoothd preferences, cached codec capability bits).
//  What it cannot do on a jailed device:
//    - Modify the A2DP codec negotiation (see A2DPHook.swift / docs).
//

import Foundation
import Combine

/// Roots catalogued by worse_query as reachable via the containermanagerd
/// escape (subset relevant to A2DP stack state).
enum A2DPProbeRoot: String, CaseIterable, Identifiable {
    // /private/var form: matches fsgetpath output and worse_query's own UI default.
    case systemData = "/private/var/containers/Data/System"
    case systemGroup = "/private/var/containers/Shared/SystemGroup"
    case internalDaemon = "/private/var/mobile/Containers/Data/InternalDaemon"
    case pluginKitPlugin = "/private/var/mobile/Containers/Data/PluginKitPlugin"
    case appGroup = "/private/var/mobile/Containers/Shared/AppGroup"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .systemData: return "System data (bluetoothd)"
        case .systemGroup: return "Shared SystemGroup"
        case .internalDaemon: return "Internal daemons"
        case .pluginKitPlugin: return "PluginKit plugins"
        case .appGroup: return "App Groups"
        }
    }
}

/// Names whose presence marks a container as Bluetooth / A2DP related.
enum BluetoothPathFilter {
    static let keywords = [
        "bluetooth",
        "blued",
        "a2dp",
        "airplay", // share audio paths with A2DP sink negotiation
        "codec"
    ]

    static func isBluetoothRelated(_ path: String) -> Bool {
        let lowered = path.lowercased()
        return keywords.contains { lowered.contains($0) }
    }

    /// Sub-path inside a container that normally holds bluetoothd preferences.
    static let preferencesSubpaths = [
        "Library/Preferences/com.apple.bluetooth.plist",
        "Library/Preferences/com.apple.bluetooth.services.plist",
        "Library/Preferences/com.apple.BluetoothFormatter.plist",
        "Library/com.apple.bluetooth"
    ]
}

/// Bluetooth stack state lives OUTSIDE the container system (no "bluetooth
/// system container" exists on iOS). These are the historical/actual paths —
/// probed directly with the escape instead of scanning containers.
enum BluetoothSystemPath {
    static let dirs: [String] = [
        "/private/var/wireless/Library/Preferences",
        "/private/var/wireless/Library/Bluetooth",
        "/private/var/wireless/Library",
        "/private/var/preferences",
        "/private/var/db"
    ]

    static let files: [String] = [
        "/private/var/wireless/Library/Preferences/com.apple.bluetooth.plist",
        "/private/var/wireless/Library/Preferences/com.apple.bluetooth.services.plist",
        "/private/var/preferences/com.apple.bluetooth.plist",
        "/private/var/preferences/com.apple.blued.plist",
        "/private/var/mobile/Library/Preferences/com.apple.bluetooth.plist"
    ]
}

struct A2DPProbeFinding: Identifiable {
    let id = UUID()
    let path: String
    let readable: Bool
    let summaryLines: [String]
}

/// Live-state probe. Publishes a console-style log plus structured findings.
@MainActor
final class A2DPProbe: ObservableObject {
    @Published var log: String = ""
    @Published var findings: [A2DPProbeFinding] = []
    @Published var running = false

    /// Root-only survivable handle for the app group (via pathleak / worse_query).
    var appGroupOverride: String?

    private var baselineInode: UInt64 = 0

    private func append(_ line: String) {
        log += line + "\n"
    }

    /// Derive an upper inode bound by creating a file in our own sandbox and
    /// rounding its inode up (same approach as worse_query's console).
    private func computeBaseline() {
        append("Calculating baseline inode…")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(".bf_baseline_\(UUID().uuidString)")
        do {
            try "bl".write(to: url, atomically: true, encoding: .utf8)
            var st = stat()
            if stat(url.path, &st) == 0 {
                baselineInode = UInt64(st.st_ino)
                append("baseline inode ≈ \(baselineInode)")
            }
            try FileManager.default.removeItem(at: url)
        } catch {
            append("baseline failed: \(error.localizedDescription)")
            baselineInode = 250_000 // conservative fallback
        }
    }

    private var group: String {
        appGroupOverride ?? "group.com.blueforge.app"
    }

    /// worse_query's flag quirk: App Group targets on iOS 26.x need different
    /// flags than everything else.
    private func altFlags(_ target: String) -> Bool {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return major == 26 && target.contains("/Containers/Shared/AppGroup")
    }

    /// The configured group first, then every group this process is actually
    /// signed with (GestaltX technique — re-signing hosts such as LiveContainer
    /// inject a different group than the development one).
    private func candidateGroups() -> [String] {
        var list = [group]
        if appGroupOverride == nil {
            let signed = (EntitlementsReader.usableAppGroups() as? [String]) ?? []
            for candidate in signed where !list.contains(candidate) {
                list.append(candidate)
            }
        }
        return list
    }

    private func ensureCaches(_ groupID: String) {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else { return }
        let caches = root.appendingPathComponent("Library/Caches")
        if (try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)) != nil {
            append("created missing Library/Caches for \(groupID)")
        }
    }

    private var loggedDefaultGroupRejection = false
    private var loggedWorkingGroup: String?

    /// Consume an extension trying every usable App Group (the -4 case is
    /// fixed by creating Library/Caches, then retrying — same as GestaltX).
    /// The default group is normally rejected once per process (the fallback
    /// signed group is the one that works), so that failure logs only once.
    func consumeFor(_ target: String) -> Int64 {
        let alt = altFlags(target)
        var lastHandle: Int64 = -1
        for (index, candidate) in candidateGroups().enumerated() {
            var handle = SandboxExtensionConsume(target, candidate, alt, false)
            if handle == -4 {
                ensureCaches(candidate)
                handle = SandboxExtensionConsume(target, candidate, alt, false)
            }
            if handle > 0 {
                if loggedWorkingGroup != candidate {
                    loggedWorkingGroup = candidate
                    append("sandbox extension issued via group \(candidate)")
                }
                return handle
            }
            lastHandle = handle
            if index == 0 {
                if handle == -5 {
                    if !loggedDefaultGroupRejection {
                        loggedDefaultGroupRejection = true
                        append("query rejected for default group \(candidate) — using signed groups")
                    }
                } else {
                    switch handle {
                    case -1: append("no accessible container for \(candidate)")
                    case -2: append("failed to resolve containermanagerd symbols (unsupported OS?)")
                    case -3: append("failed to create query")
                    case -6: append("kernel refused extension issue")
                    default: break
                    }
                }
            } else {
                switch handle {
                case -1: append("no accessible container for \(candidate)")
                case -2: append("failed to resolve containermanagerd symbols (unsupported OS?)")
                case -3: append("failed to create query")
                case -5: append("query rejected (\(candidate))")
                case -6: append("kernel refused extension issue")
                default: break
                }
            }
        }
        if lastHandle == -255 {
            append("target doesn't exist / invisible: \(target)")
        }
        return lastHandle
    }

    /// Enumerate one root: try the fast parentdir method first (extension on
    /// the root directory + plain listing — works for AppGroup/System on 27.x),
    /// then fall back to the parallel pathleak inode scan.
    func enumerate(root: A2DPProbeRoot = .systemData) async -> [String] {
        var found = await enumerateParentDir(root: root)
        if found.isEmpty {
            found = await enumeratePathleak(root: root)
        }
        let related = found.filter { BluetoothPathFilter.isBluetoothRelated($0) }
        append("scanned \(found.count) containers, \(related.count) bluetooth-related")
        for path in related {
            append("  ! \(path)")
        }
        return found
    }

    /// worse_query's "parentdir" method: consume an extension for the root
    /// directory itself and list its children (cheap, but only some roots
    /// accept a directory extension).
    private func enumerateParentDir(root: A2DPProbeRoot) async -> [String] {
        let rootPath = root.rawValue
        let entries = listDir(rootPath)
        guard !entries.isEmpty else {
            append("parentdir: no extension/listing for \(rootPath), falling back to pathleak")
            return []
        }
        append("parentdir: \(entries.count) entries under \(rootPath)")
        return entries.map { rootPath + "/" + $0 }
    }

    private func enumeratePathleak(root: A2DPProbeRoot) async -> [String] {
        computeBaselineIfNeeded()
        append("pathleak: scanning up to \(baselineInode) inodes for \(root.rawValue) (parallel, may take a while)…")
        let inodeLimit = baselineInode
        let rootPath = root.rawValue
        let found = await Task.detached(priority: .userInitiated) {
            (PathScannerEnumerate(rootPath, inodeLimit) as? [String]) ?? []
        }.value
        if found.isEmpty {
            append("pathleak: 0 results — fsgetpath may be restricted on this OS/version")
        }
        return found
    }

    private func computeBaselineIfNeeded() {
        if baselineInode == 0 { computeBaseline() }
    }

    /// Try to read a file/dir after consuming an extension; releases the handle
    /// immediately afterwards.
    func read(_ target: String) -> A2DPProbeFinding {
        let handle = consumeFor(target)
        guard handle > 0 else {
            append("  - can't access: \(target)")
            return A2DPProbeFinding(path: target, readable: false, summaryLines: [])
        }
        defer { SandboxExtensionRelease(handle) }

        var isDir: ObjCBool = false
        let fm = FileManager.default
        guard fm.fileExists(atPath: target, isDirectory: &isDir) else {
            append("  - vanished: \(target)")
            return A2DPProbeFinding(path: target, readable: false, summaryLines: [])
        }

        if isDir.boolValue {
            let entries = (try? fm.contentsOfDirectory(atPath: target)) ?? []
            let summary = entries.isEmpty
                ? ["(empty directory)"]
                : entries.prefix(40).map { "\($0)/" }
            append("  + dir \(target) — \(entries.count) entries")
            return A2DPProbeFinding(path: target, readable: true, summaryLines: Array(summary))
        }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: target)) else {
            append("  + exists but unreadable: \(target)")
            return A2DPProbeFinding(path: target, readable: false, summaryLines: [])
        }

        let summary = A2DPIntrospection.analyse(data: data, path: target)
        append("  + read \(target) (\(data.count) bytes)")
        for line in summary {
            append("    · \(line)")
        }
        return A2DPProbeFinding(path: target, readable: true, summaryLines: summary)
    }

    /// Full probe: enumerate + inspect every bluetooth-related container that
    /// pathleak can see, then read the known bluetoothd preference paths.
    func runFullProbe() {
        guard !running else { return }
        running = true
        findings = []
        log = ""
        append("Targeted A2DP probe: direct system paths, no container scanning")

        Task { [weak self] in
            guard let self else { return }
            for dir in BluetoothSystemPath.dirs {
                self.drill(dir, depth: 0)
            }
            for file in BluetoothSystemPath.files {
                let f = self.read(file)
                if f.readable {
                    self.findings.append(f)
                }
            }
            // System paths outside containers are kernel-refused; discover
            // bluetooth-named FILES inside containers by name instead.
            let discovered = await self.discoverBluetoothFiles()
            for path in discovered {
                let f = self.read(path)
                if f.readable {
                    self.findings.append(f)
                }
            }
            self.append("Probe finished — \(self.findings.count) findings")
            self.running = false
        }
    }

    /// Deep file discovery: one full-volume pathleak pass keeping only paths
    /// under container roots that mention bluetooth-ish keywords, at ANY
    /// depth. fsgetpath needs no read permission, so files inside unreadable
    /// containers are discoverable by name.
    func discoverBluetoothFiles() async -> [String] {
        computeBaselineIfNeeded()
        append("deep scan: full-volume inode pass for bluetooth-named paths (parallel)…")
        let inodeLimit = baselineInode
        let prefixes = A2DPProbeRoot.allCases.map(\.rawValue)
        let keywords = BluetoothPathFilter.keywords
        let found = await Task.detached(priority: .userInitiated) {
            (PathScannerEnumerateDeep(prefixes, inodeLimit, keywords, 200)
             as? [String]) ?? []
        }.value
        append("deep scan: \(found.count) bluetooth-named paths under containers")
        for path in found.prefix(50) {
            append("  # \(path)")
        }
        if found.count > 50 {
            append("  … and \(found.count - 50) more")
        }
        return found
    }

    /// Read a path and, if it is a readable directory, read its
    /// bluetooth-named children (depth-limited auto-drill).
    private func drill(_ path: String, depth: Int) {
        guard depth <= 2 else { return }
        let f = read(path)
        guard f.readable else { return }
        findings.append(f)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
              isDir.boolValue else { return }
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        for entry in entries where BluetoothPathFilter.isBluetoothRelated(entry) {
            drill(path + "/" + entry, depth: depth + 1)
        }
    }

    /// Render the current findings as exportable text.
    var exportText: String {
        var text = "BlueForge A2DP probe — \(Date())\n\n"
        text += log
        return text
    }

    enum ContainerClass {
        case identifier(String)
        case bluetoothPrefs
        case unknown
        case inaccessible
    }

    /// Classify a UUID-named container with a single extension consume:
    ///  1. `com.apple.containermanager.identifier` xattr (worse_query console),
    ///  2. `.com.apple.containermanagerd.metadata.plist` (MCMMetadataIdentifier),
    ///  3. fallback: presence of `Library/Preferences/com.apple.bluetooth.plist`.
    func classify(_ target: String) -> ContainerClass {
        let handle = consumeFor(target)
        guard handle > 0 else { return .inaccessible }
        defer { SandboxExtensionRelease(handle) }

        var buf = [CChar](repeating: 0, count: 512)
        let len = getxattr(target, "com.apple.containermanager.identifier", &buf, 511, 0, 0)
        if len > 0 {
            return .identifier(String(cString: buf))
        }

        // Canonical metadata file (visible in container listings):
        // .com.apple.mobile_container_manager.metadata.plist
        let metadataPath = target + "/.com.apple.mobile_container_manager.metadata.plist"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: metadataPath)),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            if let ident = plist["MCMMetadataIdentifier"] as? String {
                return .identifier(ident)
            }
            if let info = plist["MCMMetadataInfo"] as? [String: Any],
               let ident = info["MCMMetadataIdentifier"] as? String {
                return .identifier(ident)
            }
        }

        let pref = target + "/Library/Preferences/com.apple.bluetooth.plist"
        if FileManager.default.fileExists(atPath: pref) {
            return .bluetoothPrefs
        }
        return .unknown
    }

    /// One extension per container: resolve ownership and keep the
    /// Bluetooth-related ones. Sequential (each consume is an XPC round trip)
    /// with progress lines so long roots stay observable.
    func identifyBluetooth(in containers: [String]) async -> [(id: String, path: String)] {
        var hits: [(id: String, path: String)] = []
        var unknown = 0
        var inaccessible = 0
        let total = containers.count
        for (index, path) in containers.enumerated() {
            switch classify(path) {
            case .identifier(let ident):
                if BluetoothPathFilter.isBluetoothRelated(ident) {
                    append("  ! \(ident) → \(path)")
                    hits.append((ident, path))
                }
            case .bluetoothPrefs:
                append("  ! bluetooth prefs found → \(path)")
                hits.append(("(bluetooth prefs)", path))
            case .unknown:
                unknown += 1
            case .inaccessible:
                inaccessible += 1
            }
            if (index + 1) % 50 == 0 {
                append("identifying \(index + 1)/\(total)…")
                await Task.yield()
            }
        }
        append("classified \(total): \(hits.count) bluetooth, \(unknown) unidentified, \(inaccessible) inaccessible")
        return hits
    }

    // MARK: - Deep diagnostics

    /// Ground-truth access probe on one container: what exactly does a
    /// consumed extension allow? errno values make the next exploitation step
    /// decidable instead of guessed.
    func runDiagnostics() {
        guard !running else { return }
        running = true
        log = ""
        findings = []
        append("Deep diagnostics: single-container access probe")
        Task { [weak self] in
            guard let self else { return }
            let found = await self.enumerate(root: .systemData)
            guard let container = found.first else {
                self.append("no container to diagnose")
                self.running = false
                return
            }
            self.diagnose(container)
            self.running = false
        }
    }

    private func diagnose(_ path: String) {
        append("target: \(path)")
        var st = stat()
        if lstat(path, &st) == 0 {
            append("lstat ok: mode=\(String(st.st_mode, radix: 8)) uid=\(st.st_uid)")
        } else {
            append("lstat failed errno=\(errno)")
        }

        let handle = consumeFor(path)
        guard handle > 0 else {
            append("no extension handle — nothing further to test")
            return
        }
        defer { SandboxExtensionRelease(handle) }

        if let entries = try? FileManager.default.contentsOfDirectory(atPath: path) {
            append("listing ok: \(entries.count) entries")
            for entry in entries.prefix(15) {
                append("  . \(entry)")
            }
        } else {
            append("listing FAILED errno=\(errno)")
        }

        var buf = [CChar](repeating: 0, count: 512)
        let len = getxattr(path, "com.apple.containermanager.identifier", &buf, 511, 0, 0)
        if len > 0 {
            append("xattr ok: \(String(cString: buf))")
        } else {
            append("xattr failed len=\(len) errno=\(errno) (93=ENOATTR 13=EACCES 1=EPERM)")
        }

        let meta = path + "/.com.apple.mobile_container_manager.metadata.plist"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: meta)),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            append("metadata READ ok (\(data.count) bytes): "
                   + plist.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", "))
        } else {
            diagnoseOpen(meta, label: "metadata plist")
        }

        let gp = path + "/Library/Preferences/.GlobalPreferences.plist"
        diagnoseOpen(gp, label: "GlobalPreferences")

        let marker = path + "/.bfw_" + String(UUID().uuidString.prefix(8))
        if FileManager.default.createFile(atPath: marker, contents: Data("x".utf8)) {
            try? FileManager.default.removeItem(atPath: marker)
            append("WRITE OK inside container (marker created+removed)")
        } else {
            append("write refused inside container")
        }

        // Direct-file extension: the escape can also target a file path.
        let prefTarget = path + "/Library/Preferences/com.apple.bluetooth.plist"
        let fileHandle = consumeFor(prefTarget)
        if fileHandle > 0 {
            let readable = (try? Data(contentsOf: URL(fileURLWithPath: prefTarget))) != nil
            append("direct-file extension for bluetooth.plist: handle ok, readable=\(readable)")
            SandboxExtensionRelease(fileHandle)
        } else {
            append("direct-file extension for bluetooth.plist: refused (see log above)")
        }
    }

    private func diagnoseOpen(_ path: String, label: String) {
        let fd = open(path, O_RDONLY)
        if fd >= 0 {
            var tmp = stat()
            var size: Int64 = 0
            if fstat(fd, &tmp) == 0 { size = Int64(tmp.st_size) }
            close(fd)
            append("\(label) open ok: \(size) bytes")
        } else if errno == 2 {
            append("\(label) open failed errno=2 ENOENT (file absent — access itself works)")
        } else {
            append("\(label) open failed errno=\(errno) (2=ENOENT 13=EACCES 1=EPERM)")
        }
    }

    /// List a directory under an extension (full names, no decoration).
    func listDir(_ target: String) -> [String] {
        let handle = consumeFor(target)
        guard handle > 0 else {
            append("  - can't access: \(target)")
            return []
        }
        defer { SandboxExtensionRelease(handle) }
        var isDir: ObjCBool = false
        let fm = FileManager.default
        guard fm.fileExists(atPath: target, isDirectory: &isDir), isDir.boolValue else {
            append("  - not a directory: \(target)")
            return []
        }
        let entries = (try? fm.contentsOfDirectory(atPath: target)) ?? []
        append("  + list \(target) — \(entries.count) entries")
        return entries.sorted()
    }
}

/// Pure, testable introspection over plist/config payloads the probe reads.
enum A2DPIntrospection {
    static let codecKeywords = ["sbc", "aac", "aptx", "ldac", "lc3", "opus"]

    /// Does this sub-path look like a bluetoothd preference file we care about?
    static func looksLikePreferenceFile(_ subpath: String) -> Bool {
        let lowered = subpath.lowercased()
        return lowered.contains("com.apple.bluetooth")
    }

    /// Parse a plist and produce human-readable codec-related summary lines.
    static func analyse(data: Data, path: String) -> [String] {
        var lines: [String] = []
        if path.hasSuffix(".plist"),
           let obj = try? PropertyListSerialization.propertyList(
               from: data, options: [], format: nil) {
            let dict = flatten(obj as Any)
            for (key, value) in dict.sorted(by: { $0.key < $1.key }) {
                let lowered = key.lowercased() + " " + describeValue(value).lowercased()
                if let codec = codecKeywords.first(where: { lowered.contains($0) }) {
                    lines.append("codec signal [\(codec)]: \(key) = \(value)")
                }
            }
            if lines.isEmpty {
                lines.append("plist ok - \(dict.count) keys, no codec keywords")
            }
        } else if let text = String(data: data, encoding: .utf8) {
            // Textual configs: report codec mentions.
            let lowered = text.lowercased()
            for codec in codecKeywords where lowered.contains(codec) {
                let occurrence = countOccurrences(lowered, codec)
                lines.append("codec signal [\(codec)] ×\(occurrence)")
            }
            if lines.isEmpty {
                lines.append("text (\(text.count) chars), no codec keywords")
            }
        } else {
            lines.append("binary payload (\(data.count) bytes)")
        }
        return lines
    }

    static func countOccurrences(_ haystack: String, _ needle: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var idx = haystack.startIndex
        var count = 0
        while let range = haystack.range(of: needle, range: idx..<haystack.endIndex) {
            count += 1
            idx = range.upperBound
        }
        return count
    }

    /// Flatten nested dicts ("a.b.c" → value), depth-capped for perf.
    static func flatten(_ obj: Any, prefix: String = "", depth: Int = 0) -> [String: String] {
        guard depth < 6 else { return [:] }
        if let dict = obj as? [String: Any] {
            var out: [String: String] = [:]
            for (key, value) in dict {
                let composed = prefix.isEmpty ? key : "\(prefix).\(key)"
                out.merge(flatten(value, prefix: composed, depth: depth + 1)) { a, _ in a }
            }
            return out
        }
        if let array = obj as? [Any] {
            guard !array.isEmpty else { return [:] }
            var sub: [String: String] = [:]
            for element in array.prefix(8) {
                sub.merge(flatten(element, prefix: prefix, depth: depth + 1)) { a, _ in a }
            }
            if sub.isEmpty {
                return [prefix: "[\(array.count) items]"]
            }
            return sub
        }
        if let str = obj as? String {
            return [prefix: str.count > 120 ? String(str.prefix(120)) + "…" : str]
        }
        return [prefix: String(describing: obj)]
    }

    static func describeValue(_ value: Any) -> String {
        if let number = value as? NSNumber { return number.stringValue }
        if let bl = value as? Bool { return bl ? "true" : "false" }
        if let str = value as? String { return str }
        return String(describing: value)
    }
}
