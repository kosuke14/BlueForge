# A2DP sandbox access — worse_query integration

## Attribution / licensing

The escape primitives in `BlueForge/Escape/` (`SandboxEscape.m`, `PathScanner.m`)
are derived from [forcequitOS/worse_query](https://github.com/forcequitOS/worse_query)
by Taj C (forcequit), **GPL-3.0**. The license headers are preserved in those
files; they remain GPL-3.0 and any distribution of this app must comply with
GPL-3.0 for them.

## How the escape works (summary)

worse_query abuses the *containermanagerd* query API:

1. The app holds an App Group entitlement (`group.com.blueforge.app`).
2. It replaces its own App Group's `Library/Caches` with a **symlink** pointing
   at the target path.
3. It issues a class-7 (appGroup) `container_query` through
   `/usr/lib/system/libsystem_containermanager.dylib`; containermanagerd
   resolves the group through the Caches symlink and issues a sandbox
   **extension token** covering the resolved path.
4. `sandbox_extension_consume()` grants the process access to the target until
   `sandbox_extension_release()` is called.

A second primitive, `pathleak`, enumerates paths by brute-forcing inodes
through `fsgetpath()` — sandbox-restricted processes can enumerate filenames in
directories they cannot open.

Flag quirk: App Group targets on **iOS 26.x** use flag `0x0000000800000000`;
everything else uses `0x0000008000000000`. `A2DPProbe.consumeExtension(_:)`
replicates worse_query's rule.

## What BlueForge does with it

`BlueForge/A2DP/A2DPProbe.swift` — A2DP stack introspection:

- **Targeted path probe** (no container scanning): Bluetooth stack state lives
  *outside* the container system — there is no "bluetooth system container" on
  iOS. The escape issues extensions directly for the actual locations:
  `/var/wireless/Library/Preferences/com.apple.bluetooth*`,
  `/var/wireless/Library/Bluetooth/`, `/var/preferences`,
  `/var/mobile/Library/Preferences/com.apple.bluetooth.plist`.
- Readable directories are auto-drilled (depth 2) for bluetooth-named entries,
  and every readable plist is parsed for codec signals
  (`sbc`/`aac`/`aptx`/`ldac`/`lc3`) via the testable `A2DPIntrospection` helpers.
- Container enumeration (`pathleak`, parentdir) remains available for research
  (Diagnostics button) but is not part of the main probe anymore.

`BlueForge/A2DP/A2DPHook.swift` — hook strategy layer:

| Strategy | Feasible jailed? | Status |
|---|---|---|
| System state enumeration (sandbox escape) | ✅ | Implemented (`A2DPProbe`) |
| AVAudioSession route observer | ✅ | Implemented (public API; logs when an A2DP/BLE route activates) |
| bluetoothd codec override (injection) | ❌ | Refuses with explanation — see below |

## Honest limits (why the third strategy refuses)

- worse_query is a **file-access** escape. Its own README states it is not, and
  will never be, a jailbreak. There is no code-loading primitive here.
- A2DP codec negotiation runs inside `/usr/libexec/bluetoothd` (SEP/AVDTP
  negotiation against the sink). Selecting LDAC there means **injecting code
  into bluetoothd** — only possible with a jailbreak runtime (ElleKit /
  Substrate-style injection), which is out of scope for BlueForge.
- Therefore on a jailed iPhone the probe gives you ground truth about what the
  system negotiated and stored; it cannot change the negotiation. BlueForge's
  actual LDAC/LC3/SBC streams run over its own BLE GATT path (see README).

## If a jailbroken runtime is ever in scope

For documentation only (not implemented in this repo):

1. Hook bluetoothd with ElleKit: intercept the AVDTP SEP selection callbacks
   and clone of the codec table so LDAC SEPs are offered to the sink.
2. The encoder side could then reuse `AOSPBridge/LDAC` (libldacBT) in-process.
3. The `SandboxExtensionConsume` handle then becomes a persistence/inspection
   tool rather than the only door in.

## Usage notes

- The App Group identifier must match the installed build's entitlement
  (`group.com.blueforge.app` by default; override in the UI). A real App Group
  requires a provisioning profile that includes it — unsigned CI builds still
  compile the code paths.
- `-255` from `SandboxExtensionConsume` means "target doesn't exist (to us)":
  pathleak enumerates, but `lstat` needs parent traversal; treat it as
  "skip".
- Full-probe runs hit thousands of inodes; expect the enumeration step to take
  tens of seconds per root. Findings are capped per root (24) to keep the UI
  responsive.
