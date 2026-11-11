# CodecForge — treating the escape as a potential writer

## The inventor loop

The probe (see `SANDBOX_A2DP.md`) established *read* access. CodecForge stops
pretending the write question is already answered and measures it:

1. **Scan** — consume a sandbox extension for each known Bluetooth system
   directory (`/var/wireless/Library/Preferences`, `/var/wireless/Library/Bluetooth`,
   `/var/wireless/Library`, `/var/preferences`) and attempt a marker-file
   create/delete inside it. The result (`WRITABLE` vs `read-only`) is
   *measured*, never assumed — kernel extension semantics on iOS 26/27 are not
   documented publicly, and the only way to know is to try, in a way that
   cannot damage anything (unique name, immediate remove).
2. **Edit** — if (and only if) a container measures writable, its plist files
   can be loaded into an editor that shows codec-flavoured keys
   (`PLISTForge.codecLeaves` matches `sbc/aac/aptx/ldac/lc3/opus` in keys or
   values) or all keys when the "show all" toggle is on.
3. **Forge** — a transactional write-back:
   - original bytes saved once as `<file>.bf.bak` (kept even across restores),
   - new bytes written to `.bf.tmp_<uuid>`,
   - `replaceItemAt` renames the tmp over the live file (atomic on the volume),
   - any failure restores the backup before reporting.
4. **Measure the effect** — toggle Bluetooth in Control Center so bluetoothd
   reloads its persisted state, then observe what changed (route observer,
   re-probe, actual negotiation behaviour).
5. **Record** — every attempt (including failures) is appended to
   `Documents/forge_history.json` and viewable/shared in-app, so the
   experiment accumulates knowledge across builds.

## What we expect to find

- Most Data/System escapes will very likely measure **read-only**; the
  measurement is the deliverable, not guesswork.
- If any Bluetooth-state path turns out writable, the plausible wins are state
  that bluetoothd re-reads on adapter reconnect, e.g. cached per-device
  capability/codec records in `com.apple.bluetooth` preferences. If a forge
  survives a reconnect *and* flips negotiation, the discovery is huge for a
  jailed device; if bluetoothd rewrites the file back, that is also published
  knowledge via history.
- Nothing here touches another user's data or any remote system; targets are
  filtered to Bluetooth-related containers on this device.

## Restoring

`Restore from backup` swaps `path.bf.bak` back over the live file with the same
atomic routine. The backup file itself is never deleted by the app.

## Known limits

- Extensions may be read-only by design: forge buttons stay disabled unless
  the parent directory measured writable.
- Index paths (`[n]` components inside arrays) are display/read-only; dict key
  paths only can be edited.
- Values are re-typed heuristically (bool/int/double/string); exotic types
  (date/data) are not preserved by round-tripping and are excluded by showing
  leaves as text — forge deliberately shows them so users avoid those rows.
