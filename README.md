# BlueForge – Bluetooth Audio Codec Extender (jailed iOS)

A research prototype targeting **A2DP codec extension on jailed iOS**
(escape-capable versions: iOS 26.0–26.7.2 / 27.0–27.2, device-verified on
27.2). It measures Bluetooth stack state through the worse_query sandbox
escape (per-file extension reads) and experiments with measured-writable
state (CodecForge). No microphone, no media playback, no custom hardware.

## Quick start (in-app guide)

Open the app once — the guide shows up automatically (or from "Start here").
It walks the research flow with an explicit compatibility check:

1. **Compatibility**: iOS 26.0–26.7.2 / 27.0–27.2 supported (27.2 device-verified).
2. **App Group**: any signed group works — auto-detected at runtime
   (LiveContainer/SideStore hosts included).
3. **Probe**: direct per-file extension reads of Bluetooth stack state;
   daemon containers identified via their metadata plists.
4. **CodecForge**: writability measured with harmless marker files;
   writable targets get a transactional plist editor (backup, readback
   verification, auto-restore, full attempt history).
5. **Verify**: toggle Bluetooth so bluetoothd reloads state, re-probe,
   compare.

Everything lives under "上級" links on the main screen.

## Clarified goal

Extend the A2DP profile (quality/latency: LDAC-class codecs, higher sampling
rates) on **jailed, escape-capable iOS**. The app pursues this with
state-level research (probe/forge of the Bluetooth stack's persisted state)
and a design for hook integration behind a jailbreak runtime. Code injection
into bluetoothd (and any PPL-bypass-style exploit development) is out of
scope for this project; the hook layer activates only on an existing
jailbreak runtime (docs/SANDBOX_A2DP.md).

## Sample rates (USB-DAC-style behaviour)

Playback requests the codec's native rate via `AVAudioSession
setPreferredSampleRate` and reports the rate the route actually runs at.
USB audio routes honour >48 kHz (like a USB-DAC); the built-in speaker and
Bluetooth A2DP routes are capped at 48 kHz by their own hardware/negotiation
— the engine resamples and the UI shows the real output rate.

## Honest scope / limitations (read first)

1. **Jailed iPhone cannot change classic A2DP codec negotiation.** iOS decides
   the A2DP codec at the system level and does not expose it to apps. BlueForge
   therefore does not (and cannot) make the system use LDAC/aptX for normal
   Bluetooth headphones. It streams over **BLE with a custom GATT service**, so
   the receiving device must run matching firmware.

2. **Codec availability:**
   - **AAC** – native via `AVAudioConverter`.
   - **SBC** – software encoder included (approximate; replace polyphase
     filterbank with the A2DP reference for production).
   - **LDAC** – reference C impl ships in AOSP (`external/libldac`). Bridge
     via `AOSPBridge/` (Obj-C++ wrapper). See "AOSP bridging".
   - **LC3 (LE Audio)** – reference C impl ships in AOSP (`external/liblc3`).
     Bridge via `AOSPBridge/`.
   - **aptX / aptX HD / aptX LL / aptX Adaptive / aptX Lossless** – Qualcomm
     proprietary IP, **not in AOSP**, cannot be reimplemented from public
     sources. Require a Qualcomm license + SDK. Included as stubs only.

3. **LE Audio** on iOS is supported for hearing aids (iOS 17+) but general
   LE Audio broadcast/unicast to arbitrary devices is not yet exposed to apps.

## AOSP bridging

Create an `AOSPBridge/` target (Objective-C++) that compiles the AOSP C sources:

- `external/libldac/src/` → `libldacBT_enc`, `libldacBT_dec`
- `external/liblc3/src/` → `lc3_encoder`, `lc3_decoder`

Expose a small C/ObjC API to Swift, e.g.:

```objc
@interface LDACBridge : NSObject
- (instancetype)initWithSampleRate:(int)sr channels:(int)ch bitrate:(int)br;
- (NSData *)encodePCM:(NSData *)pcm;
@end
```

Then update `LDACCodec` / `LC3Codec` to call the bridge instead of throwing.

## iPhone-to-iPhone mode

The app can act as either a BLE **sender** or **receiver**, so two iPhones (or
iPhone + iPad) can stream audio directly without custom firmware.

1. Install the same build on both devices.
2. On the receiver: choose **Role → Receiver**, select the same codec/format/
   bitrate as the sender, then tap **Start Receiver**. The device advertises
   `BlueForge RX` with the custom service.
3. On the sender: choose **Role → Sender**, match the codec/format/bitrate,
   tap **Scan**, select `BlueForge RX`, then tap **Start Capture**.

Both apps must stay in the foreground for reliable advertising/connection.
Start with AAC or SBC at 128–256 kbps; LDAC at 990 kbps may exceed practical
BLE throughput. Codec/format are not negotiated automatically — both sides
must match. Received frames are decoded and played through AVAudioEngine.

## Status

Source-complete prototype (validated C bridges on Linux; iOS compile via CI):
- Codec abstraction + manager.
- AAC (native encode+decode via AVAudioConverter).
- SBC (BlueZ libsbc via AOSPBridge).
- LDAC (AOSP libldac encoder + MIT decoder via AOSPBridge).
- LC3 / LE Audio (AOSP liblc3 via AOSPBridge).
- aptX family: stubs only (Qualcomm proprietary; license required).
- BLE central sender and BLE peripheral receiver with length-prefixed frames.
- AVAudioEngine capture conversion, codec-sized framing, and playback.
- SwiftUI role/codec/format controls, XCTest suite, XcodeGen project.
- A2DP stack introspection via the worse_query sandbox-escape technique:
  sandbox extensions issued directly for the real Bluetooth state paths
  (`/var/wireless/Library/...` — no Bluetooth container exists on iOS).
  Reveals bluetoothd state/codec signals; cannot re-negotiate the A2DP codec.
  See `docs/SANDBOX_A2DP.md` and the in-app "上級" screen.
- CodecForge (experimental): the escape is treated as a *possible writer* —
  per-container writability is measured with harmless marker files, and only
  proven-writable targets get a transactional plist editor (atomic rename-in,
  `.bf.bak` backup, auto-restore on failure, per-attempt history in
  `forge_history.json`). See `docs/CODECFORGE.md`.
- LiveContainer-friendly: App Groups are discovered at runtime from the
  process's effective entitlements (SecTask, then Mach-O signature parse —
  LCSign/GestaltX technique), every signed group is tried per escape call,
  and the `Library/Caches` hole is healed before retry. See
  `docs/LIVECONTAINER.md`.

Remaining (requires Xcode/device/licensing):
- Compile & sign on a physical device.
- Obtain Qualcomm license for aptX family.
- Add sequence numbers / packet-loss recovery for production streaming.

## Building

Open `BlueForge.xcodeproj` in Xcode 15+, set signing team, build for a physical
device (BLE requires hardware). The included `.xcodeproj` is a placeholder; use
Xcode's "New Project → App" and add these source files, or generate with
`xcodegen`.

## Testing codecs

Unit tests should round-trip encode→decode for SBC/AAC/LDAC/LC3 and assert
bit-exact-ish reconstruction (lossy codecs: SNR threshold).

## License note

aptX family codecs are licensed technology. Do not attempt to reverse-engineer
or ship them without authorization. Files under `BlueForge/Escape/` are derived
from forcequitOS/worse_query (GPL-3.0).
