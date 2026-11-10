# LiveContainer compatibility

BlueForge is a plain SwiftUI app (no embedded frameworks, no dynamic libraries
beyond the system ones it dlopens at call time), so it runs inside
[LiveContainer](https://github.com/LiveContainer/LiveContainer) like any other
side-loaded app. The parts that matter for the escape are handled dynamically
rather than by bundle identity:

1. **App Group discovery at runtime** (`BlueForge/Escape/EntitlementsReader.m`,
   derived from huamidev/GestaltX, itself derived from LCSign):
   `SecTaskCopyValueForEntitlement` is queried first; if that yields nothing,
   the main image's Mach-O code signature is parsed for
   `com.apple.security.application-groups`. The app then tries **every** usable
   group (configured group first, then discovered groups) when consuming a
   sandbox extension. This is the same behaviour GestaltX relies on for
   SideStore/AltStore/LiveContainer re-signing, where the signed group differs
   from the development one.
2. **`-4` recovery**: if the chosen group's container has no `Library/Caches`
   (the escape needs it for the symlink), the directory is created and the
   query is retried (GestaltX does the same).
3. **No bundle-path assumptions**: nothing in the codebase reads its own app
   bundle path or writes next to the executable; all local state (forge
   history, Gestalt backups) lives in the Documents directory, which follows
   the host process under LiveContainer.
4. **Graceful degradation without entitlements**: if no group resolves, every
   escape call logs `no accessible container for <group>` and the UI simply
   reports the probe results as inaccessible — the codec/BLE features of
   BlueForge remain fully usable under LiveContainer.

## What to expect

- **iOS 27.x**: SystemGroup escape works (proven by GestaltX writing
  `com.apple.MobileGestalt.plist` in-place on current OS). Open
  CodecForge → MobileGestalt.plist.
- **iOS 26.x**: the containermanagerd escape works for Data/System + App Group
  paths per worse_query compatibility; GestaltX states on-device MobileGestalt
  access is *not* supported on 26.x, so treat that target as likely
  inaccessible there and let the probe report it.
- Signing: give the (re-signed) bundle at least one App Group entitlement —
  any one. The runtime discovery accepts whatever the signer embeds.

## Attribution

Files under `BlueForge/Escape/` are GPL-3.0 (forcequitOS/worse_query) and
`EntitlementsReader` additionally derived from huamidev/GestaltX (GPL-3.0) and
LCSign (LCEntitlementsReader). Distribute under GPL-3.0 terms accordingly.
