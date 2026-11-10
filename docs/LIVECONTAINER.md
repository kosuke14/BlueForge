# LiveContainer compatibility

BlueForge is a plain SwiftUI app (no embedded frameworks, no dynamic libraries
beyond the system ones it dlopens at call time), so it runs inside
[LiveContainer](https://github.com/LiveContainer/LiveContainer) like any other
side-loaded app. The parts that matter for the escape are handled dynamically
rather than by bundle identity:

## App Group: how to provide it (the common question)

You do **not** configure the App Group inside BlueForge. The escape is granted
by `containermanagerd` only when the *running process* is effectively signed
with the group — and under LiveContainer the running process is the **LC host
app**. Guest-app entitlements are emulated by LC for container URLs, but they
do not exist for kernel sandbox extension issuance. Therefore:

1. **Sign the LiveContainer host IPA with an App Group.** Add to the host's
   entitlements at signing time:
   ```xml
   <key>com.apple.security.application-groups</key>
   <array>
       <string>group.com.blueforge.app</string>
   </array>
   ```
   - ESign / paid certs: entitlements editor → add the key above (any
     `group.*` id works; paid profile required for Apple to accept groups).
   - TrollStore: free entitlement injection — just add the same key.
   - SideStore/AltStore with a **free** Apple ID: App Groups are not
     available at all, so the escape cannot work there (use a paid cert or
     TrollStore).
2. **Guest side needs nothing.** BlueForge discovers every group the process
   is effectively signed with at runtime (`SecTaskCopyValueForEntitlement`,
   falling back to Mach-O code-signature parsing — the LCSign/GestaltX
   technique) and tries them all per escape call. The in-app
   "App Group" text field is only an optional first preference; leave the
   default (`group.com.blueforge.app`) and the fallback kicks in.
3. **Verify**: run the probe/forge scan. A missing group logs
   `no accessible container for <group>` per candidate — if *every* candidate
   logs that, the host is signed without any App Group.

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
   history) lives in the Documents directory, which follows
   the host process under LiveContainer.
4. **Graceful degradation without entitlements**: if no group resolves, every
   escape call logs `no accessible container for <group>` and the UI simply
   reports the probe results as inaccessible — the codec/BLE features of
   BlueForge remain fully usable under LiveContainer.

## What to expect

- **iOS 27.x**: SystemGroup escape works (proven by GestaltX's on-device
  writes); BlueForge uses it read-only for the A2DP probe and, where a target
  measures writable, for CodecForge experiments on Bluetooth state.
- **iOS 26.x**: the containermanagerd escape works for Data/System + App Group
  paths per worse_query compatibility; let the probe report what it finds.
- Signing: give the (re-signed) bundle at least one App Group entitlement —
  any one. The runtime discovery accepts whatever the signer embeds.

## Attribution

Files under `BlueForge/Escape/` are GPL-3.0 (forcequitOS/worse_query) and
`EntitlementsReader` additionally derived from huamidev/GestaltX (GPL-3.0) and
LCSign (LCEntitlementsReader). Distribute under GPL-3.0 terms accordingly.
