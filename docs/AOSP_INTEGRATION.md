# AOSP Integration Guide

## Prerequisites
- AOSP source tree (Android 13+ for LC3).
- Xcode 15+ with a physical device target.

## LDAC
1. Copy `external/libldac/inc/` and `external/libldac/src/` into the project (or reference via submodule).
2. Add `ldacBT.h` to header search paths.
3. Uncomment the `#include` and calls in `AOSPBridge/LDACBridge.mm`.
4. Add `LDACBridge.h/.mm` and the AOSP sources to the `BlueForge` target (compile .c as C, .mm as Obj-C++).
5. Uncomment the `#import` lines in `BlueForge/Bridging-Header.h`.
6. Update `LDACCodec.swift` to instantiate `LDACBridge` and delegate encode/decode.

## LC3 (LE Audio)
1. Copy `external/liblc3/include/` and `external/liblc3/src/`.
2. Uncomment integration points in `AOSPBridge/LC3Bridge.mm`.
3. Same bridging steps as LDAC.

## SBC
The built-in Swift SBC is a simplified reference. For production, replace
`SBCEncoder.swift` with a bridge to `external/sbc` (BlueZ libsbc) or FFmpeg's
`sbcdsp`. The frame format is compatible.

## aptX family
Requires Qualcomm license + SDK. Not available in AOSP. Contact Qualcomm for
the aptX Adaptive SDK (OEM program). Integrate via a separate licensed module.

## Verification
- Run `BlueForgeTests` on a device/simulator.
- Round-trip encode→decode and compare SNR against reference implementation.
- On-device: stream to a custom BLE receiver and verify audio quality.
```
