# BlueForge – Bluetooth Audio Codec Extender (jailed iOS)

A prototype iOS app that encodes audio with a selectable Bluetooth audio codec
and streams the encoded frames over BLE to a paired receiver (custom firmware).

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
- A2DP stack introspection via the worse_query sandbox-escape technique
  (containermanagerd extension + pathleak enumeration). **Read-only on a jailed
  device** — it reveals bluetoothd state/codec signals, it cannot re-negotiate
  the A2DP codec; see `docs/SANDBOX_A2DP.md` and the in-app
  "A2DP system access" screen.
- CodecForge (experimental): the escape is treated as a *possible writer* —
  per-container writability is measured with harmless marker files, and only
  proven-writable targets get a transactional plist editor (atomic rename-in,
  `.bf.bak` backup, auto-restore on failure, per-attempt history in
  `forge_history.json`). See `docs/CODECFORGE.md`.

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
